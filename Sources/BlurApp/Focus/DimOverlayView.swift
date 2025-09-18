import AppKit

final class DimOverlayView: NSView {
    var animationDuration: TimeInterval = 0.2
    var dimColor: NSColor = .black {
        didSet { dimLayer.fillColor = dimColor.cgColor }
    }

    private let dimLayer = CAShapeLayer()
    private var lastRequestedAlpha: Float = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        dimLayer.fillColor = dimColor.cgColor
        dimLayer.opacity = 0
        dimLayer.fillRule = .evenOdd
        dimLayer.frame = bounds
        dimLayer.allowsEdgeAntialiasing = false
        layer?.addSublayer(dimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        dimLayer.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        dimLayer.contentsScale = scale
    }

    func update(
        dimAlpha: CGFloat,
        holes: [CGRect],
        cornerRadius: CGFloat,
        feather: CGFloat,
        animated: Bool
    ) {
        let path = CGMutablePath()
        let expandedBounds = bounds.insetBy(dx: -2, dy: -2)
        path.addRect(expandedBounds)

        for rect in holes {
            let roundedRect = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addPath(roundedRect.cgPath)
        }

        dimLayer.shadowOpacity = feather > 0 ? 0.35 : 0.0
        dimLayer.shadowRadius = feather
        dimLayer.shadowColor = NSColor.black.cgColor
        dimLayer.shadowOffset = .zero

        let applyChanges = {
            self.dimLayer.path = path
            self.dimLayer.opacity = Float(dimAlpha)
        }

        lastRequestedAlpha = Float(dimAlpha)

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            applyChanges()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyChanges()
            CATransaction.commit()
        }
    }

    func setHidden(_ hidden: Bool, animated: Bool) {
        let targetAlpha: Float = hidden ? 0.0 : lastRequestedAlpha

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            dimLayer.opacity = targetAlpha
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dimLayer.opacity = targetAlpha
            CATransaction.commit()
        }
    }
}
