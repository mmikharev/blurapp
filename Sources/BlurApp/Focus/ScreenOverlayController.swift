import AppKit

@MainActor
final class ScreenOverlayController {
    private(set) var screen: NSScreen
    private let window: OverlayWindow

    init(screen: NSScreen) {
        self.screen = screen
        self.window = OverlayWindow(screen: screen)
        window.orderFrontRegardless()
    }

    func updateScreenIfNeeded(_ newScreen: NSScreen) {
        guard screen != newScreen else { return }
        screen = newScreen
        window.setFrame(newScreen.frame, display: true)
        window.overlayView?.frame = NSRect(origin: .zero, size: newScreen.frame.size)
    }

    func update(dimAlpha: CGFloat, holes: [CGRect], configuration: FocusConfiguration, animated: Bool) {
        guard let overlayView = window.overlayView else { return }
        overlayView.animationDuration = configuration.animationDuration
        overlayView.update(
            dimAlpha: dimAlpha,
            holes: holes,
            cornerRadius: configuration.cornerRadius,
            feather: configuration.feather,
            animated: animated
        )
    }

    func setHidden(_ hidden: Bool, animated: Bool) {
        if hidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
        window.overlayView?.setHidden(hidden, animated: animated)
    }

    func setIgnoresMouseEvents(_ ignores: Bool) {
        window.ignoresMouseEvents = ignores
    }
}

