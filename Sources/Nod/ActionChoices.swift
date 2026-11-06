import NodCore

/// Labels for the actions a person can pick in onboarding and Settings.
enum ActionChoices {
    static let all: [(label: String, action: GestureAction)] = [
        ("Do nothing", .none), ("Dismiss notification", .dismissNotification), ("Snooze notification", .snoozeNotification),
        ("Play / pause", .playPause), ("Next track", .nextTrack), ("Previous track", .previousTrack), ("Answer FaceTime", .answerFaceTime),
        ("Decline FaceTime", .declineFaceTime),
    ]

    static func name(_ gesture: Gesture) -> String { gesture.displayName }

    /// A shortcut or Shortcuts-app action set elsewhere is shown as it is, not forced into the list.
    static func label(_ action: GestureAction) -> String {
        all.first { $0.action == action }?.label ?? { if case .runShortcut(let n) = action { "Shortcut: \(n)" } else { "Keyboard shortcut" } }()
    }
}
