import CoreGraphics
import Foundation

struct FocusConfiguration {
    var mode: FocusMode = .activeApp
    var followMouse: Bool = false
    var animationDuration: TimeInterval = 0.2
    var cornerRadius: CGFloat = 8
    var focusInset: CGFloat = 6
    var feather: CGFloat = 12
}
