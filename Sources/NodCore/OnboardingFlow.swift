import Foundation

/// First-run steps (S-01 to S-06). Raw values are stored in settings so the flow resumes where it stopped.
public enum OnboardingStep: Int, Sendable, Codable, CaseIterable, Equatable {
    case welcome, motion, airpods, calibration, assign, ready
}

/// The onboarding state machine. Pure: the views feed it events and draw `step` and the derived flags.
public struct OnboardingFlow: Sendable, Equatable {
    public enum AirPodsCheck: Sendable, Equatable { case waiting, connected, stalled }
    public enum CalibrationOutcome: Sendable, Equatable { case pending, done, skipped, retryNeeded }

    /// Seconds without motion data before the "still waiting" panel (S-03, a UI proposal, unverified).
    public static let stallAfter: TimeInterval = 10

    public private(set) var step: OnboardingStep
    public private(set) var motion: MotionAuthorization
    public private(set) var airpods: AirPodsCheck = .waiting
    public private(set) var calibration: CalibrationOutcome = .pending
    public private(set) var isFinished = false

    public init(resumeAt step: OnboardingStep = .welcome, motion: MotionAuthorization = .notDetermined) {
        self.step = step
        self.motion = motion
    }

    /// S-02 shows the "denied" panel with a button that opens System Settings.
    public var motionDenied: Bool { step == .motion && motion == .denied }

    /// "Continue" on the screens that have it: welcome, assign gestures, ready.
    public mutating func continueTapped() {
        switch step {
        case .welcome: step = .motion; advanceIfMotionAuthorized()
        case .assign: step = .ready
        case .ready: isFinished = true
        case .motion, .airpods, .calibration: break // these advance on their own events
        }
    }

    public mutating func motionAuthorizationChanged(_ value: MotionAuthorization) {
        motion = value
        if step == .motion { advanceIfMotionAuthorized() }
    }

    /// `worn` is the engine's worn signal (first motion data or a connect event).
    public mutating func headphonesWornChanged(_ worn: Bool) {
        guard step == .airpods else { return }
        if worn {
            airpods = .connected
            step = .calibration
        }
    }

    /// Call as time passes on the AirPods step.
    public mutating func waited(_ seconds: TimeInterval) {
        guard step == .airpods, airpods == .waiting, seconds >= Self.stallAfter else { return }
        airpods = .stalled
    }

    public mutating func calibrationFinished(success: Bool) {
        guard step == .calibration else { return }
        if success {
            calibration = .done
            step = .assign
        } else {
            calibration = .retryNeeded
        }
    }

    /// "Try again" after a failed calibration.
    public mutating func restartCalibration() {
        guard step == .calibration else { return }
        calibration = .pending
    }

    /// "Skip for now": the default thresholds stay.
    public mutating func skipCalibration() {
        guard step == .calibration else { return }
        calibration = .skipped
        step = .assign
    }

    private mutating func advanceIfMotionAuthorized() {
        if motion == .authorized { step = .airpods }
    }
}
