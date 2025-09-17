import AppKit

@MainActor
final class AppCoordinator {
    private let store: AppStore
    private let menuBarController: MenuBarController
    private let permissionMonitor: AccessibilityPermissionMonitor

    private var preferencesWindow: PreferencesWindowController?
    private var onboardingWindow: AccessibilityOnboardingWindowController?
    private var workspaceObserver: NSObjectProtocol?
    private var stateObserverToken: UUID?

    init(
        store: AppStore = AppStore(),
        permissionMonitor: AccessibilityPermissionMonitor = AccessibilityPermissionMonitor()
    ) {
        self.store = store
        self.permissionMonitor = permissionMonitor
        self.menuBarController = MenuBarController()
        self.menuBarController.delegate = self
    }

    func start() {
        stateObserverToken = store.subscribe { [weak self] state in
            guard let self else { return }
            self.menuBarController.refresh(using: state)
            self.preferencesWindow?.update(with: state)
        }

        registerWorkspaceObserver()
        registerInitialFrontmostApplication()

        if permissionMonitor.isAuthorized {
            store.activateFocusEngine()
        } else {
            presentOnboardingIfNeeded()
            permissionMonitor.startMonitoring { [weak self] authorized in
                guard let self else { return }
                if authorized {
                    self.permissionMonitor.stopMonitoring()
                    self.dismissOnboarding()
                    self.store.activateFocusEngine()
                }
            }
        }
    }

    func stop() {
        if let token = stateObserverToken {
            store.unsubscribe(token)
            stateObserverToken = nil
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        permissionMonitor.stopMonitoring()
        onboardingWindow?.dismiss()
        preferencesWindow?.close()
        store.shutdown()
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
        store.dispatch(.recordRecentApplication(identity))
    }
}

extension AppCoordinator: @MainActor MenuBarControllerDelegate {
    func menuBarController(_ controller: MenuBarController, didToggleEnabled isEnabled: Bool) {
        store.dispatch(.setEnabled(isEnabled))
        if isEnabled && permissionMonitor.isAuthorized {
            store.activateFocusEngine()
        }
    }

    func menuBarController(_ controller: MenuBarController, didChangeIntensity value: Double) {
        store.dispatch(.setIntensity(value))
    }

    func menuBarController(_ controller: MenuBarController, didSelectMode mode: FocusMode) {
        store.dispatch(.setMode(mode))
    }

    func menuBarController(_ controller: MenuBarController, didToggleFollowMouse isEnabled: Bool) {
        store.dispatch(.setFollowMouse(isEnabled))
    }

    func menuBarController(_ controller: MenuBarController, didRequestPause duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        store.dispatch(.schedulePause(until: deadline))
    }

    func menuBarControllerDidRequestResume(_ controller: MenuBarController) {
        store.dispatch(.cancelPause)
    }

    func menuBarController(_ controller: MenuBarController, didToggleExclusion bundleIdentifier: String) {
        store.dispatch(.toggleExclusion(bundleIdentifier))
    }

    func menuBarControllerDidRequestAddFrontmostAppToExclusions(_ controller: MenuBarController) {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
        let displayName = app.localizedName ?? bundleID
        let identity = ApplicationIdentity(bundleIdentifier: bundleID, displayName: displayName)
        store.dispatch(.addExclusion(identity))
    }

    func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
        if preferencesWindow == nil {
            let window = PreferencesWindowController()
            window.preferencesDelegate = self
            preferencesWindow = window
        }
        preferencesWindow?.update(with: store.currentState)
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
            store.activateFocusEngine()
        }
    }
}

extension AppCoordinator: @MainActor PreferencesWindowControllerDelegate {
    func preferencesController(_ controller: PreferencesWindowController, didSelectMode mode: FocusMode) {
        store.dispatch(.setMode(mode))
    }

    func preferencesController(_ controller: PreferencesWindowController, didToggleFollowMouse isEnabled: Bool) {
        store.dispatch(.setFollowMouse(isEnabled))
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeAnimationDuration value: TimeInterval) {
        store.dispatch(.setAnimationDuration(value))
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeCornerRadius value: CGFloat) {
        store.dispatch(.setCornerRadius(value))
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeFocusInset value: CGFloat) {
        store.dispatch(.setFocusInset(value))
    }

    func preferencesController(_ controller: PreferencesWindowController, didChangeFeather value: CGFloat) {
        store.dispatch(.setFeather(value))
    }
}

