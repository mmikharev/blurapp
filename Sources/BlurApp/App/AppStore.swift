import Foundation

@MainActor
final class AppStore {
    private enum Constants {
        static let maxRecentApplications = 8
    }

    private let environment: AppEnvironment
    private var observers: [UUID: (AppState) -> Void] = [:]
    private var pauseTimer: DispatchSourceTimer?
    private var isFocusEngineActive = false

    private(set) var state: AppState

    var currentState: AppState { state }

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        var initialState = environment.preferencesStore.loadState()
        if let pauseUntil = initialState.pauseUntil, pauseUntil <= environment.dateProvider() {
            initialState.pauseUntil = nil
        }
        state = initialState
    }

    @MainActor deinit {
        shutdown()
    }

    @discardableResult
    func subscribe(_ observer: @escaping (AppState) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        observer(state)
        return token
    }

    func unsubscribe(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    func dispatch(_ action: AppAction) {
        var newState = state
        let didMutate = reduce(&newState, action: action)
        if didMutate {
            let previousState = state
            state = newState
            if action.shouldPersistState {
                environment.preferencesStore.saveState(state)
            }
            synchronizeFocusEngine(from: previousState)
            notifyObservers()
        }
        handleSideEffects(for: action)
    }

    func activateFocusEngine() {
        guard !isFocusEngineActive else { return }
        configureFocusEngine()
        environment.focusEngine.start()
        isFocusEngineActive = true
        environment.focusEngine.setEnabled(isFocusEngineEnabled(for: state))
    }

    func shutdown() {
        pauseTimer?.cancel()
        pauseTimer = nil
        if isFocusEngineActive {
            environment.focusEngine.stop()
            isFocusEngineActive = false
        }
    }

    // MARK: - Reducer

    private func reduce(_ state: inout AppState, action: AppAction) -> Bool {
        switch action {
        case let .setEnabled(isEnabled):
            guard state.isEnabled != isEnabled else { return false }
            state.isEnabled = isEnabled
            return true

        case let .setIntensity(value):
            let clamped = max(0.0, min(value, 1.0))
            guard state.intensity != clamped else { return false }
            state.intensity = clamped
            return true

        case let .setMode(mode):
            guard state.mode != mode else { return false }
            state.mode = mode
            return true

        case let .setFollowMouse(isEnabled):
            guard state.followMouseEnabled != isEnabled else { return false }
            state.followMouseEnabled = isEnabled
            return true

        case let .setAnimationDuration(duration):
            guard state.animationDuration != duration else { return false }
            state.animationDuration = duration
            return true

        case let .setCornerRadius(radius):
            guard state.cornerRadius != radius else { return false }
            state.cornerRadius = radius
            return true

        case let .setFocusInset(inset):
            guard state.focusInset != inset else { return false }
            state.focusInset = inset
            return true

        case let .setFeather(feather):
            guard state.feather != feather else { return false }
            state.feather = feather
            return true

        case let .toggleExclusion(bundleIdentifier):
            if state.excludedBundleIdentifiers.contains(bundleIdentifier) {
                state.excludedBundleIdentifiers.remove(bundleIdentifier)
            } else {
                state.excludedBundleIdentifiers.insert(bundleIdentifier)
            }
            return true

        case let .addExclusion(identity):
            let inserted = state.excludedBundleIdentifiers.insert(identity.bundleIdentifier).inserted
            let recentsChanged = insertRecentApplication(identity, into: &state)
            return inserted || recentsChanged

        case let .recordRecentApplication(identity):
            return insertRecentApplication(identity, into: &state)

        case let .schedulePause(until: deadline):
            guard state.pauseUntil != deadline else { return false }
            state.pauseUntil = deadline
            return true

        case .cancelPause:
            guard state.pauseUntil != nil else { return false }
            state.pauseUntil = nil
            return true
        }
    }

    // MARK: - Helpers

    private func insertRecentApplication(_ identity: ApplicationIdentity, into state: inout AppState) -> Bool {
        var recent = state.recentApplications
        recent.removeAll { $0.bundleIdentifier == identity.bundleIdentifier }
        recent.insert(identity, at: 0)
        if recent.count > Constants.maxRecentApplications {
            recent = Array(recent.prefix(Constants.maxRecentApplications))
        }
        guard recent != state.recentApplications else { return false }
        state.recentApplications = recent
        return true
    }

    private func configureFocusEngine() {
        environment.focusEngine.setIntensity(state.intensity)
        environment.focusEngine.setExcludedBundles(state.excludedBundleIdentifiers)
        environment.focusEngine.updateConfiguration { configuration in
            configuration.mode = state.mode
            configuration.followMouse = state.followMouseEnabled
            configuration.animationDuration = state.animationDuration
            configuration.cornerRadius = state.cornerRadius
            configuration.focusInset = state.focusInset
            configuration.feather = state.feather
        }
    }

    private func synchronizeFocusEngine(from previousState: AppState) {
        guard isFocusEngineActive else { return }

        if previousState.intensity != state.intensity {
            environment.focusEngine.setIntensity(state.intensity)
        }

        if previousState.excludedBundleIdentifiers != state.excludedBundleIdentifiers {
            environment.focusEngine.setExcludedBundles(state.excludedBundleIdentifiers)
        }

        let configurationChanged =
            previousState.mode != state.mode ||
            previousState.followMouseEnabled != state.followMouseEnabled ||
            previousState.animationDuration != state.animationDuration ||
            previousState.cornerRadius != state.cornerRadius ||
            previousState.focusInset != state.focusInset ||
            previousState.feather != state.feather

        if configurationChanged {
            environment.focusEngine.updateConfiguration { configuration in
                configuration.mode = state.mode
                configuration.followMouse = state.followMouseEnabled
                configuration.animationDuration = state.animationDuration
                configuration.cornerRadius = state.cornerRadius
                configuration.focusInset = state.focusInset
                configuration.feather = state.feather
            }
        }

        let previouslyEnabled = isFocusEngineEnabled(for: previousState)
        let currentlyEnabled = isFocusEngineEnabled(for: state)
        if previouslyEnabled != currentlyEnabled {
            environment.focusEngine.setEnabled(currentlyEnabled)
        }
    }

    private func isFocusEngineEnabled(for state: AppState) -> Bool {
        let now = environment.dateProvider()
        let isPaused = state.pauseUntil.map { $0 > now } ?? false
        return state.isEnabled && !isPaused
    }

    private func handleSideEffects(for action: AppAction) {
        switch action {
        case let .schedulePause(until: deadline):
            schedulePauseTimer(until: deadline)
        case .cancelPause:
            cancelPauseTimer()
        default:
            break
        }
    }

    private func schedulePauseTimer(until deadline: Date) {
        pauseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let now = environment.dateProvider()
        let interval = max(0, deadline.timeIntervalSince(now))
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            self?.handlePauseTimerFired()
        }
        timer.resume()
        pauseTimer = timer
    }

    private func cancelPauseTimer() {
        pauseTimer?.cancel()
        pauseTimer = nil
    }

    private func handlePauseTimerFired() {
        cancelPauseTimer()
        var newState = state
        let didMutate = reduce(&newState, action: .cancelPause)
        guard didMutate else { return }
        let previousState = state
        state = newState
        synchronizeFocusEngine(from: previousState)
        notifyObservers()
    }

    private func notifyObservers() {
        observers.values.forEach { observer in
            observer(state)
        }
    }
}

