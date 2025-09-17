import AppKit

final class IntensityControlView: NSView {
    private let glassView = LiquidGlassView()
    private let titleLabel: NSTextField
    let slider: NSSlider

    override var intrinsicContentSize: NSSize {
        NSSize(width: 240, height: 80)
    }

    init(slider: NSSlider) {
        self.slider = slider
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true

        titleLabel = NSTextField(labelWithString: "Intensity")
        titleLabel.font = NSFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassView)
        glassView.addSubview(titleLabel)
        glassView.addSubview(slider)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            glassView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            titleLabel.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: glassView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: glassView.topAnchor, constant: 14),

            slider.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -16),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            slider.bottomAnchor.constraint(equalTo: glassView.bottomAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLabel(percentValue: Int) {
        titleLabel.stringValue = "Intensity • \(percentValue)%"
    }
}
