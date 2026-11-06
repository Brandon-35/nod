import AppKit
import NodCore
import SwiftUI

/// The gesture toast (S-30): a small non-activating panel near the top right that says what a gesture did, or why it
/// failed with a button that fixes it. VoiceOver gets the same text as an announcement; the panel never takes focus.
@MainActor final class ToastController {
    private let app: AppModel
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = app.engine.lastEvent
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let event = self.app.engine.lastEvent, let toast = ToastContent(event: event, enabled: self.app.settings.showToast) {
                    self.show(toast)
                }
                self.observe()
            }
        }
    }

    func show(_ toast: ToastContent) {
        hideTask?.cancel()
        let view = ToastView(toast: toast) { [weak self] fix in
            SystemSettingsLinks.open(fix == .openMotionSettings ? SystemSettingsLinks.motion : SystemSettingsLinks.accessibility)
            self?.hide()
        }
        let host = NSHostingView(rootView: view)
        host.setFrameSize(NSSize(width: 300, height: host.fittingSize.height))
        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setContentSize(host.frame.size)
        if let screen = NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 300 - 16, y: screen.visibleFrame.maxY - 8))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: toast.text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        // An error with a button stays longer so it can be reached.
        let seconds = toast.fix == nil ? 2.5 : 8.0
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.hide() }
        }
    }

    func hide() { panel?.orderOut(nil) }
}

private struct ToastView: View {
    let toast: ToastContent
    let fix: (FixAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle" : "checkmark.circle").accessibilityHidden(true)
            Text(toast.text).fixedSize(horizontal: false, vertical: true)
            if let action = toast.fix { Button(action.label) { fix(action) } }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
