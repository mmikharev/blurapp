import AppKit
import ApplicationServices
import OSLog

/// Coordinates the dimming overlays and responds to focus changes.
/// Owns per-display overlays, listens for workspace and accessibility events,
/// and queries the Accessibility API for focus windows.
@MainActor
final class FocusEngine {
    private struct Constants {
        static let refreshThrottle: TimeInterval = 0.02
        static let mouseThrottle: TimeInterval = 0.08
    }

    private let log = Logger(subsystem: "com.blurapp.core", category: "FocusEngine")
    private let windowTracker = AccessibilityWindowTracker()

    private var overlayControllers: [CGDirectDisplayID: ScreenOverlayController] = [:]
    private var configuration = FocusConfiguration()
    private var excludedBundleIdentifiers: Set<String> = []

    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var pendingRefresh: DispatchWorkItem?
    private var lastSnapshots: [WindowSnapshot] = []
    private var lastRefreshDate: Date = .distantPast

    private var appObserver: AXObserver?
    private var observedProcessIdentifier: pid_t = 0

    private(set) var isRunning = false
    private var isEnabled = true
    private var currentIntensity: CGFloat = 0.6
    private var isSuspendedBySystemUI = false

    private var lastAXEventAt: Date = .distantPast

    deinit {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        synchronizeScreens()
        registerNotifications()
        updateMouseMonitor()
        prepareObserverForFrontmostApplication()
        refreshFocus(animated: false)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        unregisterNotifications()
        pendingRefresh?.cancel()
        pendingRefresh = nil
        removeMouseMonitor()
        removeAppObserver()
        lastSnapshots.removeAll()
        overlayControllers.values.forEach { controller in
            controller.setHidden(true, animated: false)
        }
        log.debug("Focus engine stopped")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            refreshFocus(animated: true)
        } else {
            overlayControllers.values.forEach { $0.setHidden(true, animated: true) }
        }
    }

    func setIntensity(_ value: Double) {
        currentIntensity = CGFloat(clamp(value, lower: 0.0, upper: 1.0))
        applySnapshots(lastSnapshots, animated: true)
    }

    func updateConfiguration(_ transform: (inout FocusConfiguration) -> Void) {
        transform(&configuration)
        updateMouseMonitor()
        scheduleFocusRefresh(animated: true)
    }

    func setExcludedBundles(_ bundles: Set<String>) {
        excludedBundleIdentifiers = bundles
        scheduleFocusRefresh(animated: true)
    }

    func suspendForSystemUI(_ shouldSuspend: Bool) {
        guard isSuspendedBySystemUI != shouldSuspend else { return }
        isSuspendedBySystemUI = shouldSuspend
        if shouldSuspend {
            overlayControllers.values.forEach { $0.setHidden(true, animated: true) }
        } else {
            refreshFocus(animated: true)
        }
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFrontmostApplicationChanged()
        })

        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleFocusRefresh(animated: false)
        })

        let defaultCenter = NotificationCenter.default
        observers.append(defaultCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeScreens()
            self?.scheduleFocusRefresh(animated: false)
        })

        observers.append(defaultCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleFocusRefresh(animated: true)
        })

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.expose.entered"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForSystemUI(true)
        })

        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.expose.exited"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForSystemUI(false)
        })

        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.WindowManager.entered"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForSystemUI(true)
        })

        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.WindowManager.exited"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForSystemUI(false)
        })
    }

    private func unregisterNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default
        observers.forEach { token in
            workspaceCenter.removeObserver(token)
            defaultCenter.removeObserver(token)
        }
        observers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach { token in
            distributedCenter.removeObserver(token)
        }
        distributedObservers.removeAll()
    }

    private func handleFrontmostApplicationChanged() {
        removeAppObserver()
        scheduleFocusRefresh(animated: true)
        prepareObserverForFrontmostApplication()
    }

    // MARK: - Mouse Monitoring

    private func updateMouseMonitor() {
        guard isRunning else { return }
        if configuration.followMouse {
            if mouseMonitor == nil {
                var lastTimestamp: TimeInterval = 0
                mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                    guard let self else { return }
                    if lastTimestamp == 0 || (event.timestamp - lastTimestamp) >= Constants.mouseThrottle {
                        lastTimestamp = event.timestamp
                        self.scheduleFocusRefresh(animated: true)
                    }
                }
            }
        } else {
            removeMouseMonitor()
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - Refresh Logic

    private func scheduleFocusRefresh(animated: Bool) {
        guard isRunning, isEnabled, !isSuspendedBySystemUI else { return }
        pendingRefresh?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshFocus(animated: animated)
        }
        pendingRefresh = workItem

        let delay = max(0, Constants.refreshThrottle - Date().timeIntervalSince(lastRefreshDate))
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func refreshFocus(animated: Bool) {
        lastRefreshDate = Date()
        guard isRunning, isEnabled, !isSuspendedBySystemUI else { return }
        prepareObserverForFrontmostApplication()
        synchronizeScreens()

        let snapshots = windowTracker.focusedWindows(
            configuration: configuration,
            exclusions: excludedBundleIdentifiers
        )

        if snapshots.isEmpty {
            let trusted = AXIsProcessTrusted()
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            log.debug("No focus windows. trusted=\(trusted, privacy: .public) frontmost=\(bundleID, privacy: .public)")
        }

        lastSnapshots = snapshots
        applySnapshots(snapshots, animated: animated)
    }

    private func applySnapshots(_ snapshots: [WindowSnapshot], animated: Bool) {
        guard isRunning else { return }

        var snapshotsByDisplay: [CGDirectDisplayID: [WindowSnapshot]] = [:]
        for snapshot in snapshots {
            snapshotsByDisplay[snapshot.screenID, default: []].append(snapshot)
        }

        for (displayID, controller) in overlayControllers {
            guard let screen = screen(for: displayID) else { continue }
            let screenSnapshots = snapshotsByDisplay[displayID] ?? []

            if screenSnapshots.isEmpty {
                controller.setHidden(true, animated: animated)
                continue
            }

            let holes = screenSnapshots.compactMap { snapshot -> CGRect? in
                let converted = convert(snapshot.frame, toOverlayFor: screen)
                if let converted {
                    log.debug("Display \(displayID, privacy: .public) window \(snapshot.windowID, privacy: .public) global=\(snapshot.frame.debugDescription, privacy: .public) local=\(converted.debugDescription, privacy: .public) screen=\(screen.frame.debugDescription, privacy: .public)")
                } else {
                    log.debug("Display \(displayID, privacy: .public) window \(snapshot.windowID, privacy: .public) dropped; frame=\(snapshot.frame.debugDescription, privacy: .public) screen=\(screen.frame.debugDescription, privacy: .public)")
                }
                return converted
            }

            let dimAlpha = shouldHideForFullScreen(screenSnapshots: screenSnapshots, screen: screen) ? 0.0 : currentIntensity
            if dimAlpha <= 0.001 {
                controller.setHidden(true, animated: animated)
            } else {
                controller.setHidden(false, animated: animated)
                controller.update(dimAlpha: dimAlpha, holes: holes, configuration: configuration, animated: animated)
            }
        }
    }

    // MARK: - Screens

    private func synchronizeScreens() {
        let availableScreens = NSScreen.screens
        var activeIdentifiers: Set<CGDirectDisplayID> = []

        for screen in availableScreens {
            guard let displayID = screen.displayID else { continue }
            activeIdentifiers.insert(displayID)
            if let controller = overlayControllers[displayID] {
                controller.updateScreenIfNeeded(screen)
            } else {
                let controller = ScreenOverlayController(screen: screen)
                controller.setIgnoresMouseEvents(true)
                overlayControllers[displayID] = controller
            }
        }

        for (displayID, controller) in overlayControllers where !activeIdentifiers.contains(displayID) {
            controller.setHidden(true, animated: false)
            overlayControllers.removeValue(forKey: displayID)
        }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    private func convert(_ windowFrame: CGRect, toOverlayFor screen: NSScreen) -> CGRect? {
        guard let overlayFrame = screen.frameIfFinite else { return nil }
        var rect = windowFrame
        rect = rect.offsetBy(dx: -overlayFrame.origin.x, dy: -overlayFrame.origin.y)

        // AX frames are expressed with an origin at the upper-left corner of the
        // screen, while our overlay view uses the conventional AppKit origin at
        // the lower-left corner. Flip the Y coordinate so the highlight lines up
        // with the focused window in overlay coordinates.
        rect.origin.y = overlayFrame.size.height - rect.origin.y - rect.size.height

        // Removed insetBy call here as per instructions
        // rect = rect.insetBy(dx: -configuration.focusInset, dy: -configuration.focusInset)

        let screenBounds = CGRect(origin: .zero, size: overlayFrame.size)
        rect = rect.intersection(screenBounds)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let scale = screen.backingScaleFactor
        return pixelAlignedRect(rect, scale: scale)
    }

    private func shouldHideForFullScreen(screenSnapshots: [WindowSnapshot], screen: NSScreen) -> Bool {
        guard let screenFrame = screen.frameIfFinite else { return false }
        for snapshot in screenSnapshots {
            if nearlyEqual(snapshot.frame, screenFrame, tolerance: 1.0) {
                return true
            }
        }
        return false
    }

    // MARK: - Accessibility Observer

    private func prepareObserverForFrontmostApplication() {
        guard AXIsProcessTrusted() else {
            removeAppObserver()
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            removeAppObserver()
            return
        }
        let pid = app.processIdentifier
        guard pid != 0 else { return }
        if pid == observedProcessIdentifier { return }
        installObserver(for: pid)
    }

    private func installObserver(for pid: pid_t) {
        removeAppObserver()
        let appElement = AXUIElementCreateApplication(pid)

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { (_, _, notification, refcon) in
            guard let refcon else { return }
            let unmanagedSelf = Unmanaged<FocusEngine>.fromOpaque(refcon)
            let instance = unmanagedSelf.takeUnretainedValue()
            instance.handleAXNotification(notification as String)
        }, &observer)

        guard result == .success, let observer else {
            log.error("Failed to create AXObserver for pid \(pid, privacy: .public)")
            return
        }

        let notifications: [String] = [
            kAXFocusedWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification
        ]

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            let status = AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
            if status != .success {
                let name = notification as String
                log.debug("AXObserverAddNotification failed for \(name, privacy: .public) with status \(status.rawValue, privacy: .public)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        appObserver = observer
        observedProcessIdentifier = pid
        log.debug("Installed AX observer for pid \(pid, privacy: .public)")
    }

    private func handleAXNotification(_ notification: String) {
        guard shouldAcceptAXEvent() else { return }

        switch notification {
        case kAXFocusedWindowChangedNotification:
            scheduleFocusRefresh(animated: true)
        default:
            scheduleFocusRefresh(animated: false)
        }
    }

    private func removeAppObserver() {
        guard let observer = appObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        appObserver = nil
        observedProcessIdentifier = 0
    }

    // MARK: - Helpers

    private func shouldAcceptAXEvent() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastAXEventAt) < 0.03 { return false }
        lastAXEventAt = now
        return true
    }

    private func nearlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func pixelAlignedRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return rect.integral }
        var aligned = rect
        let originX = (rect.origin.x * scale).rounded(.down) / scale
        let originY = (rect.origin.y * scale).rounded(.down) / scale
        let maxX = (rect.maxX * scale).rounded(.up) / scale
        let maxY = (rect.maxY * scale).rounded(.up) / scale
        aligned.origin.x = originX
        aligned.origin.y = originY
        aligned.size.width = maxX - originX
        aligned.size.height = maxY - originY
        return aligned
    }
}

private extension NSScreen {
    /// Some screens report infinite frames briefly during hot-plug transitions.
    var frameIfFinite: CGRect? {
        guard frame.isFinite else { return nil }
        return frame
    }
}

private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
