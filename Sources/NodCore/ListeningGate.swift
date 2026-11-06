import Foundation

/// What the gate needs to know about the Mac right now.
public struct ListeningContext: Sendable, Equatable {
    public var now: TimeInterval
    /// A notification banner or a call is on screen.
    public var notificationVisible: Bool
    /// Media is playing on this Mac.
    public var mediaPlaying: Bool
    public init(now: TimeInterval, notificationVisible: Bool = false, mediaPlaying: Bool = false) {
        self.now = now
        self.notificationVisible = notificationVisible
        self.mediaPlaying = mediaPlaying
    }
}

public enum IgnoreReason: Sendable, Equatable {
    /// The gesture has no action assigned.
    case unassigned
    /// Default mode and nothing to act on: no notification (or no playing media for a media action).
    case nothingToActOn
    /// Armed mode: the first gesture of the arming double, or a gesture while not armed.
    case notArmed
}

public enum GateDecision: Sendable, Equatable {
    case run(GestureAction)
    case ignore(IgnoreReason)
}

/// Decides whether a recognised gesture may run its action. Pure state machine: no clock, no I/O.
///
/// Default decision (smallest reversible):
/// - `onlyWhenNotification`: notification actions run while a notification is visible; media actions
///   (play/pause, next track) run while a notification is visible or media is playing; keyboard shortcuts and
///   Shortcuts run only while a notification is visible, because a wrong send can be destructive.
/// - `always`: everything runs.
/// - `armWithDoubleGesture`: the arm gesture twice within `armWindow` arms for `armDuration`; the next gesture
///   runs its action once, then the gate disarms.
public struct ListeningGate: Sendable {
    public var armWindow: TimeInterval
    public var armDuration: TimeInterval
    private var firstArmGestureAt: TimeInterval?
    private var armedUntil: TimeInterval = -.infinity

    public init(armWindow: TimeInterval = 1.5, armDuration: TimeInterval = 5) {
        self.armWindow = armWindow
        self.armDuration = armDuration
    }

    public func isArmed(at now: TimeInterval) -> Bool { now < armedUntil }

    public mutating func reset() {
        firstArmGestureAt = nil
        armedUntil = -.infinity
    }

    public mutating func decide(_ gesture: Gesture, settings: Settings, context: ListeningContext) -> GateDecision {
        switch settings.listenMode {
        case .always:
            return run(settings.action(for: gesture))
        case .onlyWhenNotification:
            let action = settings.action(for: gesture)
            guard action != .none else { return .ignore(.unassigned) }
            return Self.allowedByDefault(action, context) ? .run(action) : .ignore(.nothingToActOn)
        case .armWithDoubleGesture:
            return decideArmed(gesture, settings: settings, context: context)
        }
    }

    private func run(_ action: GestureAction) -> GateDecision {
        action == .none ? .ignore(.unassigned) : .run(action)
    }

    static func allowedByDefault(_ action: GestureAction, _ context: ListeningContext) -> Bool {
        switch action {
        case .none: false
        case .playPause, .nextTrack, .previousTrack: context.notificationVisible || context.mediaPlaying
        default: context.notificationVisible
        }
    }

    private mutating func decideArmed(_ gesture: Gesture, settings: Settings, context: ListeningContext) -> GateDecision {
        let now = context.now
        if isArmed(at: now) {
            armedUntil = -.infinity
            firstArmGestureAt = nil
            return run(settings.action(for: gesture))
        }
        if gesture == settings.armGesture {
            if let first = firstArmGestureAt, now - first <= armWindow {
                firstArmGestureAt = nil
                armedUntil = now + armDuration
            } else {
                firstArmGestureAt = now
            }
        }
        return .ignore(.notArmed)
    }
}
