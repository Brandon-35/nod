import Foundation

/// Drives the calibration screen (S-04): one meter per gesture plus the amplitude `Calibrator` underneath.
/// A meter turns "got it" when a lenient classifier (half thresholds, no settle wait) sees that gesture. Any order counts.
public struct CalibrationSession: Sendable {
    public enum Meter: Sendable, Equatable { case idle, capturing, gotIt, retry }

    /// Seconds a gesture may stay "capturing" before the meter shows "retry".
    public static let retryAfter: TimeInterval = 4

    public static let order: [Gesture] = [.nod, .shake, .tiltLeft, .tiltRight]
    public private(set) var meters: [Gesture: Meter]
    private var calibrator: Calibrator
    private var classifier: GestureClassifier
    private var capturingSince: TimeInterval?

    public init(duration: TimeInterval = 10, defaults: ClassifierConfig = ClassifierConfig()) {
        calibrator = Calibrator(duration: duration, defaults: defaults)
        var lenient = defaults.scaled(angle: 0.5)
        lenient.requireCalm = false
        lenient.cooldown = 0.4
        classifier = GestureClassifier(config: lenient)
        meters = Dictionary(uniqueKeysWithValues: Self.order.map { ($0, Meter.idle) })
        meters[.nod] = .capturing
    }

    /// The gesture the screen is asking for now, nil when all four were seen.
    public var current: Gesture? { Self.order.first { meters[$0] != .gotIt } }
    public var isFinished: Bool { calibrator.isFinished || current == nil && calibrator.elapsed >= 2 }
    public var elapsed: TimeInterval { calibrator.elapsed }

    public mutating func add(_ sample: MotionSample) {
        calibrator.add(sample)
        if let gesture = classifier.process(sample), meters[gesture] != .gotIt {
            meters[gesture] = .gotIt
            capturingSince = nil
        }
        guard let now = current else { return }
        if capturingSince == nil { capturingSince = sample.t }
        if sample.t - (capturingSince ?? sample.t) > Self.retryAfter {
            meters[now] = .retry
        } else if meters[now] == .idle {
            meters[now] = .capturing
        }
    }

    public func result(now: Date = Date()) -> Result<CalibrationProfile, CalibrationError> {
        calibrator.result(now: now)
    }
}
