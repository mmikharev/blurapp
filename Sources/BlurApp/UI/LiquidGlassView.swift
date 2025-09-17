import AppKit

/// Visual effect backdrop styled to resemble Apple's "Liquid" glass surfaces.
/// Use as a container for controls that should adopt the modern macOS translucent look.
final class LiquidGlassView: NSVisualEffectView {
    init(cornerRadius: CGFloat = 14, emphasized: Bool = false) {
        super.init(frame: .zero)
        blendingMode = .withinWindow
        material = emphasized ? .hudWindow : .menu
        state = .active
        isEmphasized = emphasized
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
