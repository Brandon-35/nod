import Foundation

/// Tracks whether the AirPods are worn, from the headphones' connect/disconnect signal and the
/// sample stream. Pure: callers pass the current time, so the stale check is testable.
///
/// Motion data only arrives while the AirPods are worn (probe 2026-11-06), so a sample proves "worn".
/// The probe saw ~5 Hz when the head is still, so the 3 s silence watchdog used by a sibling project is not copied:
/// `staleAfter` is deliberately long, and `nil` disables it (disconnect alone ends "worn").
public struct WornTracker: Sendable, Equatable {
    /// Seconds of silence after which "worn" expires. shortcut: 30 s is a guess from one probe run,
    /// tune it once the on-device recordings show the longest quiet gap.
    public static let defaultStaleAfter: TimeInterval = 30

    public private(set) var isWorn = false
    private var lastActivity: TimeInterval = 0
    public let staleAfter: TimeInterval?

    public init(staleAfter: TimeInterval? = WornTracker.defaultStaleAfter) {
        self.staleAfter = staleAfter
    }

    /// Feeds one event; `now` is on the same clock as the sample timestamps.
    public mutating func handle(_ event: MotionEvent, now: TimeInterval) {
        switch event {
        case .connected:
            isWorn = true
            lastActivity = now
        case .disconnected:
            isWorn = false
        case .sample(let sample):
            isWorn = true
            lastActivity = max(lastActivity, sample.t)
        }
    }

    /// Call periodically. Expires "worn" when nothing has been heard for `staleAfter`.
    public mutating func tick(now: TimeInterval) {
        guard isWorn, let staleAfter, now - lastActivity > staleAfter else { return }
        isWorn = false
    }
}
