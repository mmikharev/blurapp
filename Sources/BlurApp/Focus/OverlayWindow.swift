import AppKit

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        hasShadow = false
        level = .screenSaver - 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: true)
        contentView = DimOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    var overlayView: DimOverlayView? {
        contentView as? DimOverlayView
    }
}
