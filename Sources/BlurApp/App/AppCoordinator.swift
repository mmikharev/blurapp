import AppKit

@MainActor
final class AppCoordinator {
    private let focusEngine: FocusEngine
    private let menuBarController: MenuBarController
    private let preferencesStore: AppPreferencesStore
    private let permissionMonitor: AccessibilityPermissionMonitor

    private var preferencesWindow: PreferencesWindowController?
    private var onboardingWindow: AccessibilityOnboardingWindowController?
    private var pauseTimer: DispatchSourceTimer?
    private var workspaceObserver: NSObjectProtocol?

    private var state: AppState {
        didSet {
            menuBarController.refresh(using: state)
            preferencesWindow?.update(with: state)
        }
    }

    init(
        focusEngine: FocusEngine = FocusEngine(),
        preferencesStore: AppPreferencesStore = .shared,
        permissionMonitor: AccessibilityPermissionMonitor = AccessibilityPermissionMonitor()
    ) {
        self.focusEngine = focusEngine
        self.preferencesStore = preferencesStore
        self.permissionMonitor = permissionMonitor
        self.state = preferencesStore.loadState()
        self.menuBarController = MenuBarController()
        self.menuBarController.delegate = self
    }

    func start() {
        menuBarController.refresh(using: state)
        registerWorkspaceObserver()
        registerInitialFrontmostApplication()

        if permissionMonitor.isAuthorized {
            activateFocusEngine()
        } else {
            presentOnboardingIfNeeded()
            permissionMonitor.startMonitoring { [weak self] authorized in
                guard let self else { return }
                if authorized {
                    self.permissionMonitor.stopMonitoring()
                    self.dismissOnboarding()
                    self.activateFocusEngine()
                }
            }
        }
    }

    func stop() {
        pauseTimer?.cancel()
        pauseTimer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        permissionMonitor.stopMonitoring()
        onboardingWindow?.dismiss()
        preferencesWindow?.close()
        focusEngine.stop()
    }

    // MARK: - Permissions

    private func presentOnboardingIfNeeded() {
        if onboardingWindow == nil {
            let controller = AccessibilityOnboardingWindowController()
            controller.onboardingDelegate = self
            onboardingWindow = controller
        }
        onboardingWindow?.present()
    }

    private func dismissOnboarding() {
        onboardingWindow?.dismiss()
        onboardingWindow = nil
    }

    private func activateFocusEngine() {
        configureFocusEngine()
        focusEngine.start()
        updateFocusEngineEnabledState()
    }

    private func configureFocusEngine() {
        focusEngine.setIntensity(state.intensity)
        focusEngine.setExcludedBundles(state.excludedBundleIdentifiers)
        focusEngine.updateConfiguration { configuration in
            configuration.mode = state.mode
            configuration.followMouse = state.followMouseEnabled
            configuration.animationDuration = state.animationDuration
            configuration.cornerRadius = state.cornerRadius
            configuration.focusInset = state.focusInset
            configuration.feather = state.feather
        }
    }

    private func updateFocusEngineEnabledState() {
        let now = Date()
        let isPaused = state.pauseUntil.map { $0 > now } ?? false
        focusEngine.setEnabled(state.isEnabled && !isPaused)
    }

    // MARK: - Workspace Tracking

    private func registerWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.trackRecentApplication(app)
            }
        }
    }

    private func registerInitialFrontmostApplication() {
        if let app = NSWorkspace.shared.frontmostApplication {
            trackRecentApplication(app)
        }
    }

    private func trackRecentApplication(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let displayName = app.localizedName ?? bundleID
        let identity = ApplicationIdentity(bundleIdentifier: bundleID, displayName: displayName)

        var recent = state.recentApplications
        recent.removeAll { $0.bundleIdentifier == bundleID }
        recent.insert(identity, at: 0)
        if recent.count > 8 {
            recent = Array(recent.prefix(8))
        }
        state.recentApplications = recent
    }

    // MARK: - Pause Handling

    private func schedulePause(until date: Date) {
        pauseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0, date.timeIntervalSinceNow))
        timer.setEventHandler { [weak self] in
            self?.pauseTimerFired()
        }
        timer.resume()
        pauseTimer = timer
        state.pauseUntil = date
        updateFocusEngineEnabledState()
    }

    private func pauseTimerFired() {
        pauseTimer?.cancel()
        pauseTimer = nil
        state.pauseUntil = nil
        updateFocusEngineEnabledState()
    }

    private func cancelPause() {
        pauseTimer?.cancel()
        pauseTimer = nil
        state.pauseUntil = nil
        updateFocusEngineEnabledState()
    }

    // MARK: - Persistence

    private func persistState() {
        preferencesStore.saveState(state)
    }
}

extension AppCoordinator: @MainActor MenuBarControllerDelegate {
    func menuBarController(_ controller: MenuBarController, didToggleEnabled isEnabled: Bool) {
        state.isEnabled = isEnabled
        persistState()
        updateFocusEngineEnabledState()
        if isEnabled && permissionMonitor.isAuthorized && !focusEngine.isRunning {
            activateFocusEngine()
        }
    }

    func menuBarController(_ controller: MenuBarController, didChangeIntensity value: Double) {
        state.intensity = value
        persistState()
        focusEngine.setIntensity(value)
    }

    func menuBarController(_ controller: MenuBarController, didSelectMode mode: FocusMode) {
        state.mode = mode
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.mode = mode
        }
    }

    func menuBarController(_ controller: MenuBarController, didToggleFollowMouse isEnabled: Bool) {
        state.followMouseEnabled = isEnabled
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.followMouse = isEnabled
        }
    }

    func menuBarController(_ controller: MenuBarController, didRequestPause duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        schedulePause(until: deadline)
    }

    func menuBarControllerDidRequestResume(_ controller: MenuBarController) {
        cancelPause()
    }

    func menuBarController(_ controller: MenuBarController, didToggleExclusion bundleIdentifier: String) {
        if state.excludedBundleIdentifiers.contains(bundleIdentifier) {
            state.excludedBundleIdentifiers.remove(bundleIdentifier)
        } else {
            state.excludedBundleIdentifiers.insert(bundleIdentifier)
        }
        persistState()
        focusEngine.setExcludedBundles(state.excludedBundleIdentifiers)
    }

    func menuBarControllerDidRequestAddFrontmostAppToExclusions(_ controller: MenuBarController) {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
        state.excludedBundleIdentifiers.insert(bundleID)
        let displayName = app.localizedName ?? bundleID
        let identity = ApplicationIdentity(bundleIdentifier: bundleID, displayName: displayName)
        if !state.recentApplications.contains(where: { $0.bundleIdentifier == bundleID }) {
            state.recentApplications.insert(identity, at: 0)
        }
        persistState()
        focusEngine.setExcludedBundles(state.excludedBundleIdentifiers)
    }

    func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
        if preferencesWindow == nil {
            let window = PreferencesWindowController()
            window.preferencesDelegate = self
            preferencesWindow = window
        }
        preferencesWindow?.update(with: state)
        preferencesWindow?.present()
    }

    func menuBarControllerDidRequestQuit(_ controller: MenuBarController) {
        NSApp.terminate(nil)
    }
}

extension AppCoordinator: @MainActor AccessibilityOnboardingDelegate {
    func accessibilityOnboardingDidRequestPrompt(_ controller: AccessibilityOnboardingWindowController) {
        permissionMonitor.requestAuthorizationPrompt()
    }

    func accessibilityOnboardingDidAcknowledge(_ controller: AccessibilityOnboardingWindowController) {
        if permissionMonitor.isAuthorized {
            permissionMonitor.stopMonitoring()
            dismissOnboarding()
            activateFocusEngine()
        }
    }
}

extension AppCoordinator: @MainActor PreferencesWindowControllerDelegate {
    func preferencesController(_ controller: PreferencesWindowController, didSelectMode mode: FocusMode) {
        state.mode = mode
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.mode = mode
        }
    }

    func preferencesController(_ controller: PreferencesWindowController, didToggleFollowMouse isEnabled: Bool) {
        state.followMouseEnabled = isEnabled
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.followMouse = isEnabled
        }
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeAnimationDuration value: TimeInterval) {
        state.animationDuration = value
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.animationDuration = value
        }
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeCornerRadius value: CGFloat) {
        state.cornerRadius = value
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.cornerRadius = value
        }
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeFocusInset value: CGFloat) {
        state.focusInset = value
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.focusInset = value
        }
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeFeather value: CGFloat) {
        state.feather = value
        persistState()
        focusEngine.updateConfiguration { configuration in
            configuration.feather = value
        }
    }
}

