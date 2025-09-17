import Foundation
import CoreGraphics
import XCTest
@testable import BlurApp

final class AppPreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppPreferencesStore!

    override func setUpWithError() throws {
        suiteName = "AppPreferencesStoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = AppPreferencesStore(userDefaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        store = nil
    }

    func testLoadStateWithoutStoredDataReturnsDefaults() {
        let state = store.loadState()
        let defaultsState = AppState()

        XCTAssertEqual(state.isEnabled, defaultsState.isEnabled)
        XCTAssertEqual(state.intensity, defaultsState.intensity)
        XCTAssertEqual(state.mode, defaultsState.mode)
        XCTAssertEqual(state.followMouseEnabled, defaultsState.followMouseEnabled)
        XCTAssertTrue(state.excludedBundleIdentifiers.isEmpty)
        XCTAssertNil(state.pauseUntil)
        XCTAssertTrue(state.recentApplications.isEmpty)
        XCTAssertEqual(state.animationDuration, defaultsState.animationDuration)
        XCTAssertEqual(state.cornerRadius, defaultsState.cornerRadius)
        XCTAssertEqual(state.focusInset, defaultsState.focusInset)
        XCTAssertEqual(state.feather, defaultsState.feather)
    }

    func testSaveStatePersistsAllFields() throws {
        var state = AppState()
        state.isEnabled = false
        state.intensity = 0.25
        state.mode = .activeWindow
        state.followMouseEnabled = true
        state.excludedBundleIdentifiers = Set(["com.example.one", "com.example.two"])
        state.animationDuration = 0.35
        state.cornerRadius = 24
        state.focusInset = 3
        state.feather = 9

        store.saveState(state)

        let storedData = try XCTUnwrap(defaults.data(forKey: "com.blurapp.preferences.v1"))
        let payload = try JSONDecoder().decode(StoredPreferencesPayload.self, from: storedData)

        XCTAssertEqual(payload.isEnabled, state.isEnabled)
        XCTAssertEqual(payload.intensity, state.intensity)
        XCTAssertEqual(payload.mode, state.mode)
        XCTAssertEqual(payload.followMouseEnabled, state.followMouseEnabled)
        XCTAssertEqual(Set(payload.excludedBundleIdentifiers), state.excludedBundleIdentifiers)
        XCTAssertEqual(payload.animationDuration, state.animationDuration)
        XCTAssertEqual(payload.cornerRadius, Double(state.cornerRadius))
        XCTAssertEqual(payload.focusInset, Double(state.focusInset))
        XCTAssertEqual(payload.feather, Double(state.feather))
    }

    func testLoadStateWithStoredDataRestoresAllFields() throws {
        let payload = StoredPreferencesPayload(
            isEnabled: false,
            intensity: 0.75,
            mode: .activeWindow,
            followMouseEnabled: true,
            excludedBundleIdentifiers: ["com.example.alpha", "com.example.beta"],
            animationDuration: 0.5,
            cornerRadius: 14,
            focusInset: 4,
            feather: 18
        )

        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: "com.blurapp.preferences.v1")

        let state = store.loadState()

        XCTAssertEqual(state.isEnabled, payload.isEnabled)
        XCTAssertEqual(state.intensity, payload.intensity)
        XCTAssertEqual(state.mode, payload.mode)
        XCTAssertEqual(state.followMouseEnabled, payload.followMouseEnabled)
        XCTAssertEqual(state.excludedBundleIdentifiers, Set(payload.excludedBundleIdentifiers))
        XCTAssertEqual(state.animationDuration, payload.animationDuration)
        XCTAssertEqual(state.cornerRadius, CGFloat(payload.cornerRadius))
        XCTAssertEqual(state.focusInset, CGFloat(payload.focusInset))
        XCTAssertEqual(state.feather, CGFloat(payload.feather))
    }

    func testLoadStateWithCorruptedDataResetsStore() {
        defaults.set(Data([0x00, 0x01]), forKey: "com.blurapp.preferences.v1")

        let state = store.loadState()
        let defaultsState = AppState()

        XCTAssertEqual(state.isEnabled, defaultsState.isEnabled)
        XCTAssertNil(defaults.data(forKey: "com.blurapp.preferences.v1"))
    }
}

private struct StoredPreferencesPayload: Codable {
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
