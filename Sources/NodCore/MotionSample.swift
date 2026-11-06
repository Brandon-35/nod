import Foundation

/// One head-motion reading. `t` is seconds on the device clock (boot-relative), never wall time:
/// samples arrive in bursts, so every rate is computed from timestamps.
public struct MotionSample: Sendable, Codable, Equatable {
    public var t: TimeInterval
    /// Attitude in radians.
    public var pitch: Double
    public var yaw: Double
    public var roll: Double
    /// Rotation rate in rad/s.
    public var rotX: Double
    public var rotY: Double
    public var rotZ: Double

    public init(t: TimeInterval, pitch: Double, yaw: Double, roll: Double,
                rotX: Double = 0, rotY: Double = 0, rotZ: Double = 0) {
        self.t = t
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.rotX = rotX
        self.rotY = rotY
        self.rotZ = rotZ
    }
}

/// What a motion source reports: readings plus the worn/not-worn signal from the headphones.
public enum MotionEvent: Sendable, Equatable {
    case sample(MotionSample)
    case connected
    case disconnected
}

/// A stream of head motion. The real one reads AirPods; `FakeMotionSource` replays a fixture.
public protocol MotionSource: Sendable {
    /// Events in arrival order. The stream ends when `stop()` is called or a replay is exhausted.
    var events: AsyncStream<MotionEvent> { get }
    func start()
    func stop()
}
