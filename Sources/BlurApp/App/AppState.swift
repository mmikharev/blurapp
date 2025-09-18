import CoreGraphics
import Foundation

struct AppState {
    var isEnabled: Bool = true
    var intensity: Double = 0.6
    var mode: FocusMode = .activeApp
    var followMouseEnabled: Bool = false
    var excludedBundleIdentifiers: Set<String> = []
    var pauseUntil: Date?
    var recentApplications: [ApplicationIdentity] = []
    var animationDuration: TimeInterval = 0.2
    var cornerRadius: CGFloat = 8
    var focusInset: CGFloat = 0
    var feather: CGFloat = 12
}

struct ApplicationIdentity: Equatable {
    let bundleIdentifier: String
    let displayName: String
}
