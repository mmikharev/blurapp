import AppKit

protocol AccessibilityOnboardingDelegate: AnyObject {
    func accessibilityOnboardingDidRequestPrompt(_ controller: AccessibilityOnboardingWindowController)
    func accessibilityOnboardingDidAcknowledge(_ controller: AccessibilityOnboardingWindowController)
}

final class AccessibilityOnboardingWindowController: NSWindowController {
    weak var onboardingDelegate: AccessibilityOnboardingDelegate?

    private let contentController: AccessibilityOnboardingViewController

    init() {
        contentController = AccessibilityOnboardingViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Enable Focus Dimming"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: window)
        window.contentViewController = contentController
        contentController.delegate = self
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

    func dismiss() {
        window?.close()
    }
}

extension AccessibilityOnboardingWindowController: AccessibilityOnboardingViewControllerDelegate {
    func onboardingViewControllerDidTapGrantAccess(_ controller: AccessibilityOnboardingViewController) {
        onboardingDelegate?.accessibilityOnboardingDidRequestPrompt(self)
    }

    func onboardingViewControllerDidTapContinue(_ controller: AccessibilityOnboardingViewController) {
        onboardingDelegate?.accessibilityOnboardingDidAcknowledge(self)
    }
}

private protocol AccessibilityOnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidTapGrantAccess(_ controller: AccessibilityOnboardingViewController)
    func onboardingViewControllerDidTapContinue(_ controller: AccessibilityOnboardingViewController)
}

private final class AccessibilityOnboardingViewController: NSViewController {
    weak var delegate: AccessibilityOnboardingViewControllerDelegate?

    private let descriptionText = "BlurApp needs Accessibility permission to read window shapes and stay aligned with your active workspace."

    override func loadView() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let glassView = LiquidGlassView(cornerRadius: 18, emphasized: true)
        contentView.addSubview(glassView)

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        glassView.addSubview(stackView)

        let titleLabel = NSTextField(labelWithString: "Grant Accessibility Access")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = NSColor.labelColor

        let bodyLabel = NSTextField(wrappingLabelWithString: descriptionText)
        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.textColor = NSColor.secondaryLabelColor

        let bulletLabel = NSTextField(wrappingLabelWithString: "• We do not capture window titles or contents\n• Permission can be revoked anytime in System Settings")
        bulletLabel.font = NSFont.systemFont(ofSize: 12)
        bulletLabel.textColor = NSColor.tertiaryLabelColor

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let grantButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(handleGrantAccess))
        grantButton.bezelStyle = .rounded
        grantButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        grantButton.contentTintColor = NSColor.controlAccentColor

        let continueButton = NSButton(title: "I've already granted access", target: self, action: #selector(handleContinue))
        continueButton.bezelStyle = .texturedRounded
        continueButton.font = NSFont.systemFont(ofSize: 13)

        buttonStack.addArrangedSubview(grantButton)
        buttonStack.addArrangedSubview(continueButton)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(bodyLabel)
        stackView.addArrangedSubview(bulletLabel)
        stackView.addArrangedSubview(buttonStack)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),

            stackView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: glassView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor, constant: -24)
        ])

        view = contentView
    }

    @objc private func handleGrantAccess() {
        delegate?.onboardingViewControllerDidTapGrantAccess(self)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleContinue() {
        delegate?.onboardingViewControllerDidTapContinue(self)
    }
}
