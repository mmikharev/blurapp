import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarController(_ controller: MenuBarController, didToggleEnabled isEnabled: Bool)
    func menuBarController(_ controller: MenuBarController, didChangeIntensity value: Double)
    func menuBarController(_ controller: MenuBarController, didSelectMode mode: FocusMode)
    func menuBarController(_ controller: MenuBarController, didToggleFollowMouse isEnabled: Bool)
    func menuBarController(_ controller: MenuBarController, didRequestPause duration: TimeInterval)
    func menuBarControllerDidRequestResume(_ controller: MenuBarController)
    func menuBarController(_ controller: MenuBarController, didToggleExclusion bundleIdentifier: String)
    func menuBarControllerDidRequestAddFrontmostAppToExclusions(_ controller: MenuBarController)
    func menuBarControllerDidRequestPreferences(_ controller: MenuBarController)
    func menuBarControllerDidRequestQuit(_ controller: MenuBarController)
}

final class MenuBarController: NSObject {
    weak var delegate: MenuBarControllerDelegate?

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let toggleItem: NSMenuItem
    private let intensityControlItem: NSMenuItem
    private let intensitySlider: NSSlider
    private let intensityControlView: IntensityControlView
    private let modeMenuItem: NSMenuItem
    private let activeAppModeItem: NSMenuItem
    private let activeWindowModeItem: NSMenuItem
    private let followMouseItem: NSMenuItem
    private let pauseMenuItem: NSMenuItem
    private let pauseStatusItem: NSMenuItem
    private let resumePauseItem: NSMenuItem
    private let exclusionsMenuItem: NSMenuItem
    private let exclusionsMenu: NSMenu
    private var exclusionItems: [String: NSMenuItem] = [:]

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        toggleItem = NSMenuItem(title: "Turn On Dimming", action: nil, keyEquivalent: "")

        intensitySlider = NSSlider(value: 60, minValue: 0, maxValue: 100, target: nil, action: nil)
        intensityControlView = IntensityControlView(slider: intensitySlider)
        intensityControlItem = NSMenuItem()

        modeMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        activeAppModeItem = NSMenuItem(title: "Active App", action: nil, keyEquivalent: "")
        activeWindowModeItem = NSMenuItem(title: "Active Window", action: nil, keyEquivalent: "")
        followMouseItem = NSMenuItem(title: "Follow Mouse", action: nil, keyEquivalent: "")
        pauseMenuItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
        pauseStatusItem = NSMenuItem(title: "Not paused", action: nil, keyEquivalent: "")
        resumePauseItem = NSMenuItem(title: "Resume Now", action: nil, keyEquivalent: "")
        exclusionsMenuItem = NSMenuItem(title: "Exclusions", action: nil, keyEquivalent: "")
        exclusionsMenu = NSMenu()
        super.init()
        configureMenu()
    }

    func refresh(using state: AppState) {
        toggleItem.title = state.isEnabled ? "Turn Off Dimming" : "Turn On Dimming"
        toggleItem.state = state.isEnabled ? .on : .off
        let intensityPercent = Int(round(state.intensity * 100))
        intensitySlider.doubleValue = state.intensity * 100.0
        intensityControlView.updateLabel(percentValue: intensityPercent)
        updateModeSelection(state.mode)
        followMouseItem.state = state.followMouseEnabled ? .on : .off
        let isPaused = state.pauseUntil.map { $0 > Date() } ?? false
        updatePauseMenu(using: state)
        updateExclusionsMenu(using: state)
        statusItem.button?.appearsDisabled = !(state.isEnabled && !isPaused)
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        statusItem.menu = menu

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.lefthalf.fill", accessibilityDescription: "BlurApp")
            button.image?.isTemplate = true
        }

        toggleItem.target = self
        toggleItem.action = #selector(handleToggle(_:))
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        intensitySlider.target = self
        intensitySlider.action = #selector(handleIntensitySlider(_:))
        intensityControlItem.view = intensityControlView
        menu.addItem(intensityControlItem)
        menu.addItem(.separator())

        let modeMenu = NSMenu()
        activeAppModeItem.target = self
        activeAppModeItem.action = #selector(handleModeSelection(_:))
        activeAppModeItem.representedObject = FocusMode.activeApp
        modeMenu.addItem(activeAppModeItem)

        activeWindowModeItem.target = self
        activeWindowModeItem.action = #selector(handleModeSelection(_:))
        activeWindowModeItem.representedObject = FocusMode.activeWindow
        modeMenu.addItem(activeWindowModeItem)

        modeMenuItem.submenu = modeMenu
        menu.addItem(modeMenuItem)

        followMouseItem.target = self
        followMouseItem.action = #selector(handleFollowMouseToggle(_:))
        menu.addItem(followMouseItem)
        menu.addItem(.separator())

        configurePauseMenu()
        menu.addItem(pauseMenuItem)

        configureExclusionsMenu()
        exclusionsMenuItem.submenu = exclusionsMenu
        menu.addItem(exclusionsMenuItem)
        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let quitItem = NSMenuItem(title: "Quit BlurApp", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateModeSelection(_ mode: FocusMode) {
        activeAppModeItem.state = mode == .activeApp ? .on : .off
        activeWindowModeItem.state = mode == .activeWindow ? .on : .off
    }

    private func configurePauseMenu() {
        let pauseMenu = NSMenu()
        let presets: [(String, TimeInterval)] = [
            ("Pause for 5 minutes", 5 * 60),
            ("Pause for 15 minutes", 15 * 60),
            ("Pause for 60 minutes", 60 * 60)
        ]
        for (title, interval) in presets {
            let item = NSMenuItem(title: title, action: #selector(handlePauseSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            pauseMenu.addItem(item)
        }

        pauseMenu.addItem(.separator())
        pauseStatusItem.isEnabled = false
        pauseMenu.addItem(pauseStatusItem)

        resumePauseItem.target = self
        resumePauseItem.action = #selector(handleResumePause)
        pauseMenu.addItem(resumePauseItem)

        pauseMenuItem.submenu = pauseMenu
    }

    private func configureExclusionsMenu() {
        exclusionsMenu.autoenablesItems = false
    }

    private func updatePauseMenu(using state: AppState) {
        let now = Date()
        if let pauseUntil = state.pauseUntil, pauseUntil > now {
            let remaining = pauseUntil.timeIntervalSince(now)
            pauseStatusItem.title = "Paused – \(formattedInterval(remaining)) remaining"
            resumePauseItem.isEnabled = true
        } else {
            pauseStatusItem.title = "Not paused"
            resumePauseItem.isEnabled = false
        }
    }

    private func updateExclusionsMenu(using state: AppState) {
        exclusionsMenu.removeAllItems()
        exclusionItems.removeAll()

        let recent = state.recentApplications
        if recent.isEmpty && state.excludedBundleIdentifiers.isEmpty {
            let empty = NSMenuItem(title: "No apps available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            exclusionsMenu.addItem(empty)
        } else {
            for app in recent {
                let item = NSMenuItem(title: app.displayName, action: #selector(handleExclusionToggle(_:)), keyEquivalent: "")
                item.target = self
                item.state = state.excludedBundleIdentifiers.contains(app.bundleIdentifier) ? .on : .off
                item.representedObject = app.bundleIdentifier
                exclusionItems[app.bundleIdentifier] = item
                exclusionsMenu.addItem(item)
            }

            let additional = state.excludedBundleIdentifiers.filter { bundle in
                !recent.contains(where: { $0.bundleIdentifier == bundle })
            }
            if !additional.isEmpty {
                if !recent.isEmpty {
                    exclusionsMenu.addItem(.separator())
                }
                for bundle in additional.sorted() {
                    let title = bundle
                    let item = NSMenuItem(title: title, action: #selector(handleExclusionToggle(_:)), keyEquivalent: "")
                    item.target = self
                    item.state = .on
                    item.representedObject = bundle
                    exclusionItems[bundle] = item
                    exclusionsMenu.addItem(item)
                }
            }
        }

        exclusionsMenu.addItem(.separator())
        let addItem = NSMenuItem(title: "Add Frontmost App", action: #selector(handleAddFrontmostApp), keyEquivalent: "")
        addItem.target = self
        exclusionsMenu.addItem(addItem)
    }

    private func formattedInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }

    @objc private func handleToggle(_ sender: NSMenuItem) {
        let willEnable = sender.state != .on
        delegate?.menuBarController(self, didToggleEnabled: willEnable)
    }

    @objc private func handleIntensitySlider(_ sender: NSSlider) {
        let percentValue = sender.doubleValue
        intensityControlView.updateLabel(percentValue: Int(round(percentValue)))
        delegate?.menuBarController(self, didChangeIntensity: percentValue / 100.0)
    }

    @objc private func handleModeSelection(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? FocusMode else { return }
        delegate?.menuBarController(self, didSelectMode: mode)
    }

    @objc private func handleFollowMouseToggle(_ sender: NSMenuItem) {
        let willEnable = sender.state != .on
        delegate?.menuBarController(self, didToggleFollowMouse: willEnable)
    }

    @objc private func handlePauseSelection(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? TimeInterval else { return }
        delegate?.menuBarController(self, didRequestPause: duration)
    }

    @objc private func handleResumePause() {
        delegate?.menuBarControllerDidRequestResume(self)
    }

    @objc private func handleExclusionToggle(_ sender: NSMenuItem) {
        guard let bundleIdentifier = sender.representedObject as? String else { return }
        delegate?.menuBarController(self, didToggleExclusion: bundleIdentifier)
    }

    @objc private func handleAddFrontmostApp() {
        delegate?.menuBarControllerDidRequestAddFrontmostAppToExclusions(self)
    }

    @objc private func openPreferences() {
        delegate?.menuBarControllerDidRequestPreferences(self)
    }

    @objc private func quitApp() {
        delegate?.menuBarControllerDidRequestQuit(self)
    }
}
