import Foundation

struct AppEnvironment {
    var focusEngine: FocusEngine
    var preferencesStore: AppPreferencesStore
    var dateProvider: () -> Date

    static func live(
        focusEngine: FocusEngine,
        preferencesStore: AppPreferencesStore,
        dateProvider: @escaping () -> Date
    ) -> AppEnvironment {
        AppEnvironment(
            focusEngine: focusEngine,
            preferencesStore: preferencesStore,
            dateProvider: dateProvider
        )
    }

    @MainActor static func live() -> AppEnvironment {
        let engine = FocusEngine()
        let prefs = AppPreferencesStore.shared
        let now: () -> Date = Date.init
        return AppEnvironment(
            focusEngine: engine,
            preferencesStore: prefs,
            dateProvider: now
        )
    }
}
