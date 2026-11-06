import Foundation

/// Every tunable of the classifier in one place. Defaults start from the probe of 2026-11-06
/// (nod: pitch range > 0.25 rad, shake: yaw range > 0.35 rad, both in 0.8 s). The spec window is 600 ms,
/// so the window is shorter than the probe's 0.8 s.
/// None of these numbers is proven on a real head; live tests showed they need tuning.
public struct ClassifierConfig: Sendable, Equatable, Codable {
    /// Sliding window length in seconds.
    public var window: TimeInterval = 0.6
    /// Minimum peak-to-peak angle inside the window, per axis, in radians.
    public var minPitchRange = 0.25
    public var minYawRange = 0.35
    public var minRollRange = 0.25
    /// Minimum peak angular speed in rad/s (computed from timestamps, not from sample counts).
    public var minPeakSpeed = 1.5
    /// Out-and-back check: total variation must be at least this multiple of the range, so a one-way turn
    /// (looking at a second screen) does not count.
    public var minReversalRatio = 1.6
    /// The winning axis must move at least this many times more than each other axis.
    public var dominance = 1.5
    /// Seconds of silence after a hit.
    public var cooldown: TimeInterval = 0.9
    /// A gap longer than this between two samples starts a new window (data arrives in clusters).
    public var maxGap: TimeInterval = 1.0
    /// Speed is measured across at least this much time, so jitter on closely spaced samples is not read as speed.
    public var speedSpan: TimeInterval = 0.04
    /// After a hit, wait for the head to settle (every axis moving less than half its threshold over `calmSpan`)
    /// before the next hit, so one long shake is not counted twice.
    public var requireCalm = true
    public var calmSpan: TimeInterval = 0.4
    /// Time constant in seconds of the resting-roll estimate that gives the tilt direction.
    public var restingRollTau: TimeInterval = 3
    /// Assumption until the on-device recordings confirm it: leaning left makes roll negative.
    public var leftIsNegativeRoll = true

    public init() {}

    /// A copy with every angle threshold multiplied by `factor` (sensitivity).
    public func scaled(angle factor: Double) -> ClassifierConfig {
        scaled(pitch: factor, yaw: factor, roll: factor)
    }

    /// A copy with each axis threshold multiplied by its own factor (calibration).
    public func scaled(pitch: Double, yaw: Double, roll: Double) -> ClassifierConfig {
        var c = self
        c.minPitchRange *= pitch
        c.minYawRange *= yaw
        c.minRollRange *= roll
        return c
    }
}

/// Turns a stream of samples into gestures. Pure and deterministic: feed samples in order, get a gesture or nil.
public struct GestureClassifier: Sendable {
    public var config: ClassifierConfig
    private var window: [MotionSample] = []
    private var quietUntil: TimeInterval = -.infinity
    private var needsCalm = false
    /// Slow estimate of the resting roll, fed by samples that leave the window.
    private var restingRoll: Double?
    private var restingRollT: TimeInterval = 0

    public init(config: ClassifierConfig = ClassifierConfig()) {
        self.config = config
    }

    /// Forget buffered samples, e.g. when the AirPods are taken off.
    public mutating func reset() {
        window.removeAll(keepingCapacity: true)
        quietUntil = -.infinity
        needsCalm = false
        restingRoll = nil
    }

    public mutating func process(_ sample: MotionSample) -> Gesture? {
        if let last = window.last {
            if sample.t <= last.t { return nil }
            if sample.t - last.t > config.maxGap { window.removeAll(keepingCapacity: true) }
        }
        window.append(sample)
        let oldest = sample.t - config.window
        if let firstKept = window.firstIndex(where: { $0.t >= oldest }), firstKept > 0 {
            for old in window[..<firstKept] { feedRestingRoll(old) }
            window.removeFirst(firstKept)
        }
        guard sample.t >= quietUntil else { return nil }
        if needsCalm {
            guard isCalm() else { return nil }
            needsCalm = false
        }
        guard window.count >= 4, let gesture = classify() else { return nil }
        quietUntil = sample.t + config.cooldown
        needsCalm = config.requireCalm
        window.removeAll(keepingCapacity: true)
        return gesture
    }

    private mutating func feedRestingRoll(_ s: MotionSample) {
        guard let rest = restingRoll else { restingRoll = s.roll; restingRollT = s.t; return }
        let alpha = 1 - exp(-max(0, s.t - restingRollT) / config.restingRollTau)
        restingRoll = rest + alpha * (s.roll - rest)
        restingRollT = s.t
    }

    /// True when the last `calmSpan` seconds hold at least two samples and little movement on every axis.
    private func isCalm() -> Bool {
        guard let last = window.last, let first = window.first, last.t - first.t >= config.calmSpan * 0.9 else { return false }
        let p = axis(\.pitch), y = axis(\.yaw), r = axis(\.roll)
        return p.range < 0.5 * config.minPitchRange && y.range < 0.5 * config.minYawRange && r.range < 0.5 * config.minRollRange
    }

    // MARK: Internals

    private struct Axis {
        var range = 0.0
        var variation = 0.0
        var peakSpeed = 0.0
        /// Signed deviation of the furthest point from `baseline` (the window mean when none is given).
        var excursion = 0.0
    }

    private func axis(_ value: (MotionSample) -> Double, baseline: Double? = nil) -> Axis {
        var a = Axis()
        let values = window.map(value)
        guard let lo = values.min(), let hi = values.max() else { return a }
        a.range = hi - lo
        for i in 1..<values.count { a.variation += abs(values[i] - values[i - 1]) }
        let mean = baseline ?? values.reduce(0, +) / Double(values.count)
        a.excursion = abs(hi - mean) >= abs(lo - mean) ? hi - mean : lo - mean
        // Peak speed across spans of at least `speedSpan`.
        var j = 0
        for i in 1..<window.count {
            while j < i - 1, window[i].t - window[j + 1].t >= config.speedSpan { j += 1 }
            let dt = window[i].t - window[j].t
            if dt >= config.speedSpan { a.peakSpeed = max(a.peakSpeed, abs(values[i] - values[j]) / dt) }
        }
        return a
    }

    private func classify() -> Gesture? {
        let pitch = axis(\.pitch), yaw = axis(\.yaw)
        let roll = axis(\.roll, baseline: restingRoll)
        struct Candidate { var gesture: Gesture; var score: Double }
        var best: Candidate?

        func consider(_ a: Axis, others: [Axis], need: Double, _ gesture: Gesture) {
            guard a.range >= need, a.peakSpeed >= config.minPeakSpeed,
                  a.variation >= config.minReversalRatio * a.range,
                  others.allSatisfy({ a.range >= config.dominance * $0.range }) else { return }
            let score = a.range / need
            if best == nil || score > best!.score { best = Candidate(gesture: gesture, score: score) }
        }
        consider(pitch, others: [yaw, roll], need: config.minPitchRange, .nod)
        consider(yaw, others: [pitch, roll], need: config.minYawRange, .shake)
        let tilt: Gesture = (roll.excursion < 0) == config.leftIsNegativeRoll ? .tiltLeft : .tiltRight
        consider(roll, others: [pitch, yaw], need: config.minRollRange, tilt)
        return best?.gesture
    }
}
