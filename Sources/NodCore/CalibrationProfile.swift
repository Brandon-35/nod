import Foundation

/// Result of the 10-second calibration: how big this person's natural movements are, as a factor on
/// each default angle threshold. Raw samples are never stored.
public struct CalibrationProfile: Sendable, Codable, Equatable {
    /// Safe limits: calibration can loosen or tighten a threshold by this much and no more.
    public static let factorRange = 0.6...1.6

    public var calibratedAt: Date
    public var pitchFactor: Double
    public var yawFactor: Double
    public var rollFactor: Double
    /// Mean head attitude while calibrating ("looking straight"), radians.
    public var restingPitch: Double
    public var restingYaw: Double
    public var restingRoll: Double

    public init(calibratedAt: Date, pitchFactor: Double, yawFactor: Double, rollFactor: Double = 1,
                restingPitch: Double = 0, restingYaw: Double = 0, restingRoll: Double = 0) {
        self.calibratedAt = calibratedAt
        self.pitchFactor = pitchFactor
        self.yawFactor = yawFactor
        self.rollFactor = rollFactor
        self.restingPitch = restingPitch
        self.restingYaw = restingYaw
        self.restingRoll = restingRoll
    }

    public func apply(to config: ClassifierConfig) -> ClassifierConfig {
        config.scaled(pitch: pitchFactor, yaw: yawFactor, roll: rollFactor)
    }
}

public enum CalibrationError: Error, Equatable, Sendable {
    /// Not enough samples, or the head hardly moved: keep the defaults and ask the person to try again.
    case insufficientMovement
}

/// Collects samples for `duration` seconds of device time and turns the person's biggest nod and shake into
/// thresholds: half their peak movement, clamped to `CalibrationProfile.factorRange`.
public struct Calibrator: Sendable {
    public let duration: TimeInterval
    /// Threshold as a fraction of the person's own peak movement.
    public static let targetFraction = 0.5
    private let window: TimeInterval
    private let defaults: ClassifierConfig
    private var samples: [MotionSample] = []

    public init(duration: TimeInterval = 10, defaults: ClassifierConfig = ClassifierConfig()) {
        self.duration = duration
        self.defaults = defaults
        self.window = defaults.window
    }

    public var isFinished: Bool {
        guard let first = samples.first, let last = samples.last else { return false }
        return last.t - first.t >= duration
    }

    /// Seconds collected so far, for the progress ring.
    public var elapsed: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.t - first.t
    }

    public mutating func add(_ sample: MotionSample) {
        if let last = samples.last, sample.t <= last.t { return }
        if let first = samples.first, sample.t - first.t > duration { return }
        samples.append(sample)
    }

    public func result(now: Date = Date()) -> Result<CalibrationProfile, CalibrationError> {
        guard samples.count >= 20, elapsed >= duration * 0.5 else { return .failure(.insufficientMovement) }
        let pitchPeak = peakRange(\.pitch), yawPeak = peakRange(\.yaw), rollPeak = peakRange(\.roll)
        // Nod and shake are required; a head that moved less than the default threshold on either gives no basis.
        guard pitchPeak >= defaults.minPitchRange, yawPeak >= defaults.minYawRange else { return .failure(.insufficientMovement) }
        func factor(_ peak: Double, _ threshold: Double) -> Double {
            min(max(Self.targetFraction * peak / threshold, CalibrationProfile.factorRange.lowerBound), CalibrationProfile.factorRange.upperBound)
        }
        let n = Double(samples.count)
        return .success(CalibrationProfile(
            calibratedAt: now,
            pitchFactor: factor(pitchPeak, defaults.minPitchRange),
            yawFactor: factor(yawPeak, defaults.minYawRange),
            // Roll is not asked for in the 10 seconds: keep the default unless the person happened to tilt.
            rollFactor: rollPeak >= defaults.minRollRange ? factor(rollPeak, defaults.minRollRange) : 1,
            restingPitch: samples.reduce(0) { $0 + $1.pitch } / n,
            restingYaw: samples.reduce(0) { $0 + $1.yaw } / n,
            restingRoll: samples.reduce(0) { $0 + $1.roll } / n))
    }

    /// Largest peak-to-peak value of an axis inside any window of `window` seconds.
    private func peakRange(_ value: KeyPath<MotionSample, Double>) -> Double {
        var best = 0.0, start = 0
        for end in samples.indices {
            while samples[end].t - samples[start].t > window { start += 1 }
            let slice = samples[start...end].map { $0[keyPath: value] }
            best = max(best, (slice.max() ?? 0) - (slice.min() ?? 0))
        }
        return best
    }
}
