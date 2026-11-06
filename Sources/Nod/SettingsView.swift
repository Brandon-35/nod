import NodCore
import ServiceManagement
import SwiftUI

/// Settings window (S-20 to S-24). Plain `Form`s: system controls give VoiceOver labels, Tab order and focus rings,
/// and nothing here uses a fixed height or an animation, so Dynamic Type and Reduce Motion need no special case.
struct SettingsView: View {
    let app: AppModel
    var recalibrate: () -> Void = {}
    @State private var loginError: String?

    var body: some View {
        TabView {
            gestures.tabItem { Label("Gestures", systemImage: "waveform") }
            listening.tabItem { Label("Listening", systemImage: "ear") }
            calibration.tabItem { Label("Calibration", systemImage: "slider.horizontal.3") }
            privacy.tabItem { Label("Privacy", systemImage: "lock.shield") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 360)
        .padding()
    }

    // MARK: Gestures (S-20)

    private var gestures: some View {
        Form {
            ForEach(NodCore.Gesture.allCases, id: \.self) { gesture in
                let current = app.settings.action(for: gesture)
                Picker(ActionChoices.name(gesture), selection: Binding(get: { current }, set: { value in
                    app.update { $0.setAction(value, for: gesture) }
                })) {
                    ForEach(options(including: current), id: \.label) { Text($0.label).tag($0.action) }
                }
            }
            if app.settings.mappings.allSatisfy({ $0.action == .none }) {
                Text("No gesture does anything yet. Pick an action above.").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { app.settings.sensitivity }, set: { v in app.update { $0.sensitivity = v } }),
                   in: Settings.sensitivityRange) { Text("Sensitivity") }
                .accessibilityValue(String(format: "%.1f", app.settings.sensitivity))
            Toggle("Show a confirmation after each gesture", isOn: Binding(get: { app.settings.showToast }, set: { v in app.update { $0.showToast = v } }))
            Toggle("Open Nod at login", isOn: Binding(get: { app.settings.launchAtLogin }, set: setLaunchAtLogin))
            if let loginError { Text(loginError).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
    }

    private func options(including action: GestureAction) -> [(label: String, action: GestureAction)] {
        ActionChoices.all.contains { $0.action == action } ? ActionChoices.all : ActionChoices.all + [(ActionChoices.label(action), action)]
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            app.update { $0.launchAtLogin = on }
        } catch {
            loginError = "Could not change this. Open System Settings > General > Login Items."
        }
    }

    // MARK: Listening mode (S-21)

    private var listening: some View {
        Form {
            Picker("Listening mode", selection: Binding(get: { app.listenMode }, set: { app.listenMode = $0 })) {
                Text("Only when a notification is showing (recommended)").tag(ListeningMode.onlyWhenNotification)
                Text("Always").tag(ListeningMode.always)
                Text("Arm with a double gesture").tag(ListeningMode.armWithDoubleGesture)
            }
            .pickerStyle(.radioGroup)
            Text("Nodding along to music can look like a gesture. The recommended mode avoids that.").foregroundStyle(.secondary)
            if app.listenMode == .onlyWhenNotification, app.settings.mappings.contains(where: { $0.action == .playPause || $0.action == .nextTrack || $0.action == .previousTrack }) {
                Text("Play / pause and track skipping also work while media is playing.").foregroundStyle(.secondary)
            }
            if app.listenMode == .armWithDoubleGesture {
                Picker("Arm gesture", selection: Binding(get: { app.settings.armGesture }, set: { g in app.update { $0.armGesture = g } })) {
                    ForEach(NodCore.Gesture.allCases, id: \.self) { Text(ActionChoices.name($0)).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Calibration (S-22)

    private var calibration: some View {
        Form {
            if let profile = app.settings.calibration {
                Text("Calibrated \(profile.calibratedAt.formatted(date: .abbreviated, time: .shortened)).")
                Button("Calibrate again", action: recalibrate)
                Button("Reset to defaults") { app.update { $0.calibration = nil } }
            } else {
                Text("Using the default thresholds.")
                Button("Calibrate", action: recalibrate)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Privacy and permissions (S-23)

    private var privacy: some View {
        Form {
            Text("No account. No telemetry. Everything runs on your Mac.")
            permissionRow("Motion access", granted: app.motionAuthorization() == .authorized, url: SystemSettingsLinks.motion)
            if app.settings.mappings.contains(where: { $0.action.needsAccessibility }) {
                permissionRow("Accessibility", granted: app.permissions.accessibilityGranted, url: SystemSettingsLinks.accessibility)
            } else {
                Text("Accessibility: not needed by your current gestures.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ name: String, granted: Bool, url: URL) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle" : "exclamationmark.triangle").accessibilityHidden(true)
            Text(granted ? "\(name): on" : "\(name): off")
            Spacer()
            if !granted { Button("Open System Settings") { SystemSettingsLinks.open(url) } }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: About

    private var about: some View {
        Form {
            Text("Nod \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")").font(.title2.bold())
            Text("Control your Mac with a nod.")
            Text("No account. No telemetry. Everything runs on your Mac.").foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
