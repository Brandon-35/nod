import AppKit
import SwiftUI
import NodCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var toast: ToastController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboarding: OnboardingModel?
    private var calibrationWindow: NSWindow?
    private var calibrationFlow: OnboardingModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(model: model) { [weak self] in self?.showSettings() }
        toast = ToastController(app: model)
        model.start()
        if !model.settings.onboardingCompleted { showOnboarding() }
        if ProcessInfo.processInfo.environment["NOD_OPEN_SETTINGS"] == "1" { showSettings() } // smoke test: builds every tab
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(app: model) { [weak self] in self?.showCalibration() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Nod Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Settings > Calibration: the onboarding calibration step on its own.
    private func showCalibration() {
        let flow = OnboardingModel(app: model, calibrationOnly: true)
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: flow)))
        window.title = "Calibrate Nod"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        flow.onFinish = { [weak window] in window?.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { flow.end() }
        }
        window.center()
        calibrationFlow = flow
        calibrationWindow = window
        flow.begin()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// First-run flow. Closing the window keeps the step, so the next launch resumes there.
    private func showOnboarding() {
        let flow = OnboardingModel(app: model)
        flow.onFinish = { [weak self] in self?.onboardingWindow?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: flow)))
        window.title = "Welcome to Nod"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboarding = flow
        onboardingWindow = window
        flow.begin()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
