import AppKit
import NodCore
import Observation

/// Drives the first-run window: feeds `OnboardingFlow` from the engine and permissions once a second.
/// `simulated` skips the real permission dialogs and plays a synthetic calibration.
@MainActor @Observable final class OnboardingModel {
    private(set) var flow: OnboardingFlow
    private(set) var session = CalibrationSession()
    private(set) var deviceName: String?
    var onFinish: () -> Void = {}
    let app: AppModel
    @ObservationIgnored private var waited: TimeInterval = 0
    @ObservationIgnored private var calibrationWaited: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?

    /// Wall seconds with no samples before calibration gives up and offers a retry.
    static let calibrationTimeout: TimeInterval = 20

    /// Settings > Calibration > "Calibrate again": run only the calibration step, then close. Leaves the first-run state alone.
    let calibrationOnly: Bool

    init(app: AppModel, calibrationOnly: Bool = false) {
        self.app = app
        self.calibrationOnly = calibrationOnly
        flow = OnboardingFlow(resumeAt: calibrationOnly ? .calibration : app.settings.onboardingStep, motion: app.motionAuthorization())
    }

    var step: OnboardingStep { flow.step }

    func begin() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if flow.step == .calibration { startCalibration() }
    }

    func end() {
        timer?.invalidate()
        app.engine.sampleTap = nil
    }

    func continueTapped() {
        flow.continueTapped()
        afterStepChange()
    }

    func skipCalibration() {
        app.engine.sampleTap = nil
        flow.skipCalibration()
        afterStepChange()
    }

    func retryCalibration() { startCalibration() }

    func openMotionSettings() { SystemSettingsLinks.open(SystemSettingsLinks.motion) }
    func openAccessibilitySettings() { SystemSettingsLinks.open(SystemSettingsLinks.accessibility) }

    func assign(_ action: GestureAction, to gesture: Gesture) {
        app.update { $0.setAction(action, for: gesture) }
    }

    var accessibilityNeeded: Bool {
        !app.permissions.accessibilityGranted && app.settings.mappings.contains { $0.action.needsAccessibility }
    }

    private func tick() {
        flow.motionAuthorizationChanged(app.motionAuthorization())
        if flow.step == .airpods {
            waited += 1
            flow.headphonesWornChanged(app.engine.isWorn)
            flow.waited(waited)
            if flow.step == .calibration { deviceName = app.simulated ? "Simulated AirPods" : "AirPods"; startCalibration() }
        } else if flow.step == .calibration, flow.calibration == .pending {
            calibrationWaited += 1
            if session.isFinished { finishCalibration() }
            else if calibrationWaited > Self.calibrationTimeout { flow.calibrationFinished(success: false) }
        }
        afterStepChange()
    }

    private func startCalibration() {
        session = CalibrationSession()
        calibrationWaited = 0
        flow.restartCalibration()
        if app.simulated {
            for sample in SyntheticMotion.sequence([.nod, .shake, .tiltLeft, .tiltRight], gap: 0.3) { session.add(sample) }
        } else {
            app.engine.sampleTap = { [weak self] sample in self?.session.add(sample) }
        }
    }

    private func finishCalibration() {
        app.engine.sampleTap = nil
        switch session.result() {
        case .success(let profile):
            app.update { $0.calibration = profile }
            flow.calibrationFinished(success: true)
        case .failure:
            flow.calibrationFinished(success: false)
        }
    }

    private func afterStepChange() {
        if calibrationOnly { return finishIf(flow.step != .calibration) }
        let step = flow.step
        let finished = flow.isFinished
        let stored = app.settings
        guard stored.onboardingStep != step || (finished && !stored.onboardingCompleted) else { return finishIf(finished) }
        app.update {
            $0.onboardingStep = step
            if finished { $0.onboardingCompleted = true }
        }
        finishIf(finished)
    }

    private func finishIf(_ finished: Bool) {
        if finished { end(); onFinish() }
    }
}
