import AppKit

final class PreferenceSliderRow: NSView {
    let slider: NSSlider
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField

    init(title: String, minValue: Double, maxValue: Double, tickMarkCount: Int = 0) {
        slider = NSSlider(value: minValue, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        slider.numberOfTickMarks = tickMarkCount

        titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor

        valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = NSFont.systemFont(ofSize: 12)
        valueLabel.textColor = NSColor.secondaryLabelColor
        valueLabel.alignment = .right

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, NSView(), valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 4

        addSubview(stack)
        addSubview(slider)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor),
            slider.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateValueLabel(_ text: String) {
        valueLabel.stringValue = text
    }
}
