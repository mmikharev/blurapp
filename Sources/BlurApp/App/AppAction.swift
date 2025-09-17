import CoreGraphics
import Foundation

/// Defines state mutations the application can perform.
enum AppAction {
    case setEnabled(Bool)
    case setIntensity(Double)
    case setMode(FocusMode)
    case setFollowMouse(Bool)
    case setAnimationDuration(TimeInterval)
    case setCornerRadius(CGFloat)
    case setFocusInset(CGFloat)
    case setFeather(CGFloat)
    case toggleExclusion(String)
    case addExclusion(ApplicationIdentity)
    case recordRecentApplication(ApplicationIdentity)
    case schedulePause(until: Date)
    case cancelPause
}

extension AppAction {
    /// Indicates whether the action should trigger persistence.
    var shouldPersistState: Bool {
        switch self {
        case .setEnabled,
             .setIntensity,
             .setMode,
             .setFollowMouse,
             .setAnimationDuration,
             .setCornerRadius,
             .setFocusInset,
             .setFeather,
             .toggleExclusion,
             .addExclusion:
            return true
        case .recordRecentApplication,
             .schedulePause,
             .cancelPause:
            return false
        }
    }
}
