import Foundation

struct AppEnvironment {
    var focusEngine: FocusEngine
    var preferencesStore: AppPreferencesStore
    var dateProvider: () -> Date

    static func live(
        focusEngine: FocusEngine = FocusEngine(),
        preferencesStore: AppPreferencesStore = .shared,
        dateProvider: @escaping () -> Date = Date.init
    ) -> AppEnvironment {
        AppEnvironment(
            focusEngine: focusEngine,
            preferencesStore: preferencesStore,
            dateProvider: dateProvider
        )
    }
}
