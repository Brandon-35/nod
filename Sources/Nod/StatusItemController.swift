import AppKit
import NodCore
import Observation

/// The menu bar icon and menu (S-10). The icon follows `GestureEngine.status`; the menu's first row says the
/// same thing in words, so the icon is never the only signal.
@MainActor final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        render()
    }

    static func title(for status: GestureEngine.Status) -> String { status.message.title }

    private static func symbol(for status: GestureEngine.Status) -> String {
        switch status {
        case .listening: "waveform.circle.fill"
        case .paused: "pause.circle"
        case .notWorn, .noAirPods, .unsupportedHeadphones: "waveform.circle"
        case .motionDenied, .accessibilityMissing: "exclamationmark.triangle"
        }
    }

    /// Redraws the icon and re-arms observation of the engine so the next status change redraws again.
    private func render() {
        let status = withObservationTracking { model.engine.status } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        let title = Self.title(for: status)
        item.button?.image = NSImage(systemSymbolName: Self.symbol(for: status), accessibilityDescription: "Nod: \(title)")
        item.button?.appearsDisabled = status == .notWorn || status == .noAirPods
        item.button?.setAccessibilityLabel("Nod: \(title)")
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = model.engine.status
        let header = NSMenuItem(title: Self.title(for: status), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        // Problem states say the cause and the fix in words (S-11 to S-14, S-12), not only through the icon.
        if let detail = status.message.detail {
            let row = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            row.isEnabled = false
            row.attributedTitle = NSAttributedString(string: detail, attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(row)
        }
        if let fix = status.message.fix {
            let item = NSMenuItem(title: fix.label, action: #selector(runFix(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = fix == .openMotionSettings ? "motion" : "accessibility"
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: model.engine.isPaused ? "Resume gestures" : "Pause gestures", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let modeItem = NSMenuItem(title: "Listening mode", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (mode, title) in [(ListeningMode.onlyWhenNotification, "Only when a notification is showing"),
                              (.always, "Always"), (.armWithDoubleGesture, "Arm with a double gesture")] {
            let entry = NSMenuItem(title: title, action: #selector(pickMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = model.listenMode == mode ? .on : .off
            sub.addItem(entry)
        }
        modeItem.submenu = sub
        menu.addItem(modeItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Nod", action: #selector(about), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nod", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() { model.engine.isPaused.toggle(); render() }
    @objc private func runFix(_ sender: NSMenuItem) {
        SystemSettingsLinks.open(sender.representedObject as? String == "motion" ? SystemSettingsLinks.motion : SystemSettingsLinks.accessibility)
    }

    @objc private func settingsClicked() { openSettings() }
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = ListeningMode(rawValue: raw) { model.listenMode = mode }
    }
}
