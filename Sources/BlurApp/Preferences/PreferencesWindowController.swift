import AppKit

protocol PreferencesWindowControllerDelegate: AnyObject {
    func preferencesController(_ controller: PreferencesWindowController, didSelectMode mode: FocusMode)
    func preferencesController(_ controller: PreferencesWindowController, didToggleFollowMouse isEnabled: Bool)
    func preferencesController(_ controller: PreferencesWindowController, didChangeAnimationDuration value: TimeInterval)
    func preferencesController(_ controller: PreferencesWindowController, didChangeCornerRadius value: CGFloat)
    func preferencesController(_ controller: PreferencesWindowController, didChangeFocusInset value: CGFloat)
    func preferencesController(_ controller: PreferencesWindowController, didChangeFeather value: CGFloat)
}

final class PreferencesWindowController: NSWindowController {
    weak var preferencesDelegate: PreferencesWindowControllerDelegate? {
        didSet {
            contentController.delegate = preferencesDelegate
        }
    }

    private let contentController = PreferencesViewController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlurApp Preferences"
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces]

        super.init(window: window)
        window.contentViewController = contentController
        contentController.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(with state: AppState) {
        contentController.update(with: state)
    }
}

private final class PreferencesViewController: NSViewController {
    weak var delegate: PreferencesWindowControllerDelegate?
    weak var controller: PreferencesWindowController?

    private let glassView = LiquidGlassView(cornerRadius: 24, emphasized: false)
    private let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let followMouseCheck = NSButton(checkboxWithTitle: "Follow Window Under Cursor", target: nil, action: nil)
    private let animationSliderRow = PreferenceSliderRow(title: "Animation Duration", minValue: 0, maxValue: 0.4)
    private let cornerSliderRow = PreferenceSliderRow(title: "Corner Radius", minValue: 0, maxValue: 32)
    private let insetSliderRow = PreferenceSliderRow(title: "Focus Inset", minValue: 0, maxValue: 20)
    private let featherSliderRow = PreferenceSliderRow(title: "Feather", minValue: 0, maxValue: 32)

    override func loadView() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        glassView.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: "General")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

        modePopUp.translatesAutoresizingMaskIntoConstraints = false
        modePopUp.addItems(withTitles: ["Active App", "Active Window"])
        modePopUp.target = self
        modePopUp.action = #selector(handleModeChanged)

        followMouseCheck.target = self
        followMouseCheck.action = #selector(handleFollowMouseToggle(_:))

        configureSlider(animationSliderRow.slider, selector: #selector(handleAnimationSlider(_:)))
        configureSlider(cornerSliderRow.slider, selector: #selector(handleCornerSlider(_:)))
        configureSlider(insetSliderRow.slider, selector: #selector(handleInsetSlider(_:)))
        configureSlider(featherSliderRow.slider, selector: #selector(handleFeatherSlider(_:)))

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(makeLabeledRow(label: "Focus Mode", control: modePopUp))
        stack.addArrangedSubview(followMouseCheck)
        stack.addArrangedSubview(animationSliderRow)
        stack.addArrangedSubview(cornerSliderRow)
        stack.addArrangedSubview(insetSliderRow)
        stack.addArrangedSubview(featherSliderRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: glassView.topAnchor, constant: 24)
        ])

        view = contentView
    }

    func update(with state: AppState) {
        switch state.mode {
        case .activeApp:
            modePopUp.selectItem(at: 0)
        case .activeWindow:
            modePopUp.selectItem(at: 1)
        }

        followMouseCheck.state = state.followMouseEnabled ? .on : .off

        animationSliderRow.slider.doubleValue = state.animationDuration
        animationSliderRow.updateValueLabel(String(format: "%.0f ms", state.animationDuration * 1000))

        cornerSliderRow.slider.doubleValue = state.cornerRadius
        cornerSliderRow.updateValueLabel(String(format: "%.0f px", state.cornerRadius))

        insetSliderRow.slider.doubleValue = state.focusInset
        insetSliderRow.updateValueLabel(String(format: "%.0f px", state.focusInset))

        featherSliderRow.slider.doubleValue = state.feather
        featherSliderRow.updateValueLabel(String(format: "%.0f px", state.feather))
    }

    private func configureSlider(_ slider: NSSlider, selector: Selector) {
        slider.target = self
        slider.action = selector
    }

    private func makeLabeledRow(label: String, control: NSView) -> NSView {
        let textLabel = NSTextField(labelWithString: label)
        textLabel.font = NSFont.systemFont(ofSize: 13)
        let stack = NSStackView(views: [textLabel, NSView(), control])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    @objc private func handleModeChanged() {
        guard let controller else { return }
        let selectedMode: FocusMode = modePopUp.indexOfSelectedItem == 0 ? .activeApp : .activeWindow
        delegate?.preferencesController(controller, didSelectMode: selectedMode)
    }

    @objc private func handleFollowMouseToggle(_ sender: NSButton) {
        guard let controller else { return }
        delegate?.preferencesController(controller, didToggleFollowMouse: sender.state == .on)
    }

    @objc private func handleAnimationSlider(_ sender: NSSlider) {
        guard let controller else { return }
        animationSliderRow.updateValueLabel(String(format: "%.0f ms", sender.doubleValue * 1000))
        delegate?.preferencesController(controller, didChangeAnimationDuration: sender.doubleValue)
    }

    @objc private func handleCornerSlider(_ sender: NSSlider) {
        guard let controller else { return }
        cornerSliderRow.updateValueLabel(String(format: "%.0f px", sender.doubleValue))
        delegate?.preferencesController(controller, didChangeCornerRadius: CGFloat(sender.doubleValue))
    }

    @objc private func handleInsetSlider(_ sender: NSSlider) {
        guard let controller else { return }
        insetSliderRow.updateValueLabel(String(format: "%.0f px", sender.doubleValue))
        delegate?.preferencesController(controller, didChangeFocusInset: CGFloat(sender.doubleValue))
    }

    @objc private func handleFeatherSlider(_ sender: NSSlider) {
        guard let controller else { return }
        featherSliderRow.updateValueLabel(String(format: "%.0f px", sender.doubleValue))
        delegate?.preferencesController(controller, didChangeFeather: CGFloat(sender.doubleValue))
    }
}
