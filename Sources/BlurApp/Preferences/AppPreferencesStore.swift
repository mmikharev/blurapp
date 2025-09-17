import Foundation

private struct PreferencesPayload: Codable {
    var isEnabled: Bool
    var intensity: Double
    var mode: FocusMode
    var followMouseEnabled: Bool
    var excludedBundleIdentifiers: [String]
    var animationDuration: Double
    var cornerRadius: Double
    var focusInset: Double
    var feather: Double
}

@MainActor
final class AppPreferencesStore {
    static let shared = AppPreferencesStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageKey = "com.blurapp.preferences.v1"

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
    }

    func loadState() -> AppState {
        guard let data = defaults.data(forKey: storageKey) else {
            return AppState()
        }

        do {
            let payload = try decoder.decode(PreferencesPayload.self, from: data)
            var state = AppState()
            state.isEnabled = payload.isEnabled
            state.intensity = payload.intensity
            state.mode = payload.mode
            state.followMouseEnabled = payload.followMouseEnabled
            state.excludedBundleIdentifiers = Set(payload.excludedBundleIdentifiers)
            state.animationDuration = payload.animationDuration
            state.cornerRadius = CGFloat(payload.cornerRadius)
            state.focusInset = CGFloat(payload.focusInset)
            state.feather = CGFloat(payload.feather)
            return state
        } catch {
            defaults.removeObject(forKey: storageKey)
            return AppState()
        }
    }

    func saveState(_ state: AppState) {
        let payload = PreferencesPayload(
            isEnabled: state.isEnabled,
            intensity: state.intensity,
            mode: state.mode,
            followMouseEnabled: state.followMouseEnabled,
            excludedBundleIdentifiers: Array(state.excludedBundleIdentifiers),
            animationDuration: state.animationDuration,
            cornerRadius: Double(state.cornerRadius),
            focusInset: Double(state.focusInset),
            feather: Double(state.feather)
        )

        do {
            let data = try encoder.encode(payload)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Silently ignore encoding errors to avoid impacting runtime.
        }
    }
}
