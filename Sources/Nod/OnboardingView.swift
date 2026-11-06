import NodCore
import SwiftUI

/// First-run window (S-01 to S-06). Strings come from design/copy.md.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.step {
            case .welcome: welcome
            case .motion: motion
            case .airpods: airpods
            case .calibration: calibration
            case .assign: assign
            case .ready: ready
            }
        }
        .padding(32)
        .frame(width: 560, alignment: .leading)
        .frame(minHeight: 320, alignment: .top)
    }

    private func title(_ text: String) -> some View { Text(text).font(.title.bold()).accessibilityAddTraits(.isHeader) }
    private func button(_ label: String, prominent: Bool = true, action: @escaping () -> Void) -> some View {
        Button(label, action: action).buttonStyle(.borderedProminent).controlSize(.large).tint(prominent ? .accentColor : .gray)
    }

    private var welcome: some View {
        Group {
            title("Control your Mac with a nod.")
            Text("Wear your AirPods and use head gestures to answer your Mac without touching the keyboard.")
            button("Continue") { model.continueTapped() }
        }
    }

    private var motion: some View {
        Group {
            title("Allow motion access")
            Text("Nod needs motion data from your AirPods. It only arrives while they're in your ears, and it never leaves your Mac.")
            if model.flow.motionDenied {
                Label("Motion access is off. Turn it on in System Settings to use head gestures.", systemImage: "exclamationmark.triangle")
                button("Open System Settings") { model.openMotionSettings() }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var airpods: some View {
        Group {
            title("Connect your AirPods")
            Text("Put your AirPods in your ears.")
            if model.flow.airpods == .stalled {
                Label("Still waiting for motion data. Make sure your AirPods are in your ears.", systemImage: "airpods")
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var calibration: some View {
        Group {
            title("Quick calibration")
            Text("This takes about 10 seconds and fits Nod to your head.")
            if let name = model.deviceName { Text("Connected: \(name)").foregroundStyle(.secondary) }
            Text("Look straight ahead, then nod, shake, and tilt left and right.")
            ForEach(CalibrationSession.order, id: \.self) { gesture in
                HStack {
                    Text(gestureName(gesture)).frame(width: 90, alignment: .leading)
                    Text(meterText(model.session.meters[gesture] ?? .idle)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                if model.flow.calibration == .retryNeeded {
                    Text("That didn't register. Try again.")
                    button("Try again") { model.retryCalibration() }
                }
                button("Skip for now", prominent: false) { model.skipCalibration() }
            }
        }
    }

    private var assign: some View {
        Group {
            title("Choose what each gesture does")
            ForEach(NodCore.Gesture.allCases, id: \.self) { gesture in
                Picker(gestureName(gesture), selection: binding(for: gesture)) {
                    ForEach(Self.choices, id: \.label) { Text($0.label).tag($0.action) }
                }
            }
            if model.accessibilityNeeded {
                Label("This action needs Accessibility access.", systemImage: "hand.raised")
                button("Open System Settings", prominent: false) { model.openAccessibilitySettings() }
            }
            button("Continue") { model.continueTapped() }
        }
    }

    private var ready: some View {
        Group {
            title("You're ready.")
            Text("Nod listens while a notification is showing. You can change this in Settings.")
            button("Done") { model.continueTapped() }
        }
    }

    private func binding(for gesture: NodCore.Gesture) -> Binding<GestureAction> {
        Binding(get: { model.app.settings.action(for: gesture) }, set: { model.assign($0, to: gesture) })
    }

    static let choices = ActionChoices.all
    private func gestureName(_ g: NodCore.Gesture) -> String { ActionChoices.name(g) }

    private func meterText(_ meter: CalibrationSession.Meter) -> String {
        switch meter {
        case .idle: "waiting"
        case .capturing: "go ahead"
        case .gotIt: "got it"
        case .retry: "not yet"
        }
    }
}
