import Foundation

public extension Gesture {
    var displayName: String {
        switch self {
        case .nod: "Nod"
        case .shake: "Shake"
        case .tiltLeft: "Tilt left"
        case .tiltRight: "Tilt right"
        }
    }
}

/// A button that fixes a problem by opening the right System Settings pane.
public enum FixAction: Sendable, Equatable {
    case openMotionSettings
    case openAccessibilitySettings

    public var label: String { "Open System Settings" }
}

/// Words for a menu bar state: a short title, and for problem states a cause plus what to do (S-11 to S-14, S-12).
public struct StatusMessage: Sendable, Equatable {
    public var title: String
    public var detail: String?
    public var fix: FixAction?
}

public extension GestureEngine.Status {
    var message: StatusMessage {
        switch self {
        case .listening: StatusMessage(title: "Listening")
        case .paused: StatusMessage(title: "Gestures paused")
        case .notWorn: StatusMessage(title: "Not worn", detail: "Your AirPods aren't in your ears. Put them in to start.")
        case .noAirPods: StatusMessage(title: "No AirPods", detail: "No AirPods connected. Connect your AirPods to use gestures.")
        case .unsupportedHeadphones:
            StatusMessage(title: "Unsupported headphones",
                          detail: "These headphones don't have motion sensors, so Nod can't read head gestures.")
        case .motionDenied:
            StatusMessage(title: "Needs permission", detail: "Motion access is off. Turn it on in System Settings to use head gestures.",
                          fix: .openMotionSettings)
        case .accessibilityMissing:
            StatusMessage(title: "Needs permission", detail: "Nod lost access it needs. Open System Settings to restore it.",
                          fix: .openAccessibilitySettings)
        }
    }
}

private extension StatusMessage {
    init(title: String) { self.init(title: title, detail: nil, fix: nil) }
}

/// What the gesture toast says (S-30). Nil means no toast: the setting is off, the gesture was ignored, or it maps to nothing.
public struct ToastContent: Sendable, Equatable {
    public var text: String
    public var isError: Bool
    public var fix: FixAction?

    public init?(event: GestureEvent, enabled: Bool) {
        guard enabled else { return nil }
        switch event.outcome {
        case .ignored: return nil
        case .ran:
            guard let done = Self.pastTense(event.action) else { return nil }
            text = "\(event.gesture.displayName): \(done)"
            isError = false
            fix = nil
        case .failed(let error):
            text = "That action couldn't run. \(error.message)"
            isError = true
            fix = error == .accessibilityNotGranted ? .openAccessibilitySettings : nil
        }
    }

    private static func pastTense(_ action: GestureAction) -> String? {
        switch action {
        case .none: nil
        case .dismissNotification: "dismissed notification"
        case .snoozeNotification: "snoozed notification"
        case .playPause: "play/pause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case .volumeUp: "volume up"
        case .volumeDown: "volume down"
        case .toggleMute: "mute toggled"
        case .screenshot: "screenshot"
        case .missionControl: "Mission Control"
        case .answerFaceTime: "answered FaceTime call"
        case .declineFaceTime: "declined FaceTime call"
        case .keyboardShortcut: "pressed shortcut"
        case .runShortcut(let name): "ran \(name)"
        }
    }
}
