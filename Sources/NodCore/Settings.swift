import Foundation

/// A keyboard shortcut to send to the frontmost app. `keyCode` is a virtual key code (kVK_*).
public struct KeyCombo: Sendable, Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var command = false, option = false, control = false, shift = false
    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

/// What a gesture does. Parameters live in the case.
public enum GestureAction: Sendable, Codable, Equatable, Hashable {
    case none
    case dismissNotification
    case snoozeNotification
    case playPause
    case nextTrack
    case previousTrack
    case answerFaceTime
    case declineFaceTime
    case keyboardShortcut(KeyCombo)
    case runShortcut(String)

    /// Whether the action needs the Accessibility permission (everything except Shortcuts, which run in a child process).
    public var needsAccessibility: Bool {
        switch self {
        case .none, .runShortcut: false
        default: true
        }
    }

    /// Actions that only make sense while a notification or call is on screen.
    public var needsNotification: Bool {
        switch self {
        case .dismissNotification, .snoozeNotification, .answerFaceTime, .declineFaceTime: true
        default: false
        }
    }
}

/// When the app listens for gestures.
public enum ListeningMode: String, Sendable, Codable, CaseIterable, Equatable {
    /// Default: only while a notification is showing, which removes most false positives from nodding to music.
    case onlyWhenNotification
    /// A double gesture arms listening for a few seconds.
    case armWithDoubleGesture
    case always
}

public struct GestureMapping: Sendable, Codable, Equatable {
    public var gesture: Gesture
    public var action: GestureAction
    public init(gesture: Gesture, action: GestureAction) {
        self.gesture = gesture
        self.action = action
    }
}

/// Everything the user can change. Stored locally as JSON (no account, no telemetry).
public struct Settings: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion = Settings.currentSchemaVersion
    public var listenMode: ListeningMode = .onlyWhenNotification
    /// The gesture that, done twice, arms listening in `armWithDoubleGesture` mode.
    public var armGesture: Gesture = .nod
    public var launchAtLogin = false
    /// The small "Nod: dismissed notification" confirmation after each gesture (S-30).
    public var showToast = true
    public var cooldownMs = 900
    /// Multiplies every angle threshold: above 1 is less sensitive. Clamped to `sensitivityRange`.
    public var sensitivity = 1.0
    public var mappings: [GestureMapping] = Settings.defaultMappings
    /// Set by calibration; nil means defaults.
    public var calibration: CalibrationProfile?
    /// First-run flow: the step to resume at, and whether it was finished (S-01 to S-06).
    public var onboardingStep: OnboardingStep = .welcome
    public var onboardingCompleted = false

    public static let sensitivityRange = 0.5...2.0

    /// Smallest reversible defaults (a project default): nod dismisses, shake skips a track,
    /// tilt left plays/pauses, tilt right is unassigned until the user picks a Shortcut.
    public static let defaultMappings: [GestureMapping] = [
        .init(gesture: .nod, action: .dismissNotification),
        .init(gesture: .shake, action: .nextTrack),
        .init(gesture: .tiltLeft, action: .playPause),
        .init(gesture: .tiltRight, action: .none),
    ]

    public init() {}

    /// Tolerant: a missing key keeps its default, so adding a field never makes an old file unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        listenMode = try c.decodeIfPresent(ListeningMode.self, forKey: .listenMode) ?? d.listenMode
        armGesture = try c.decodeIfPresent(Gesture.self, forKey: .armGesture) ?? d.armGesture
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        cooldownMs = try c.decodeIfPresent(Int.self, forKey: .cooldownMs) ?? d.cooldownMs
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        mappings = try c.decodeIfPresent([GestureMapping].self, forKey: .mappings) ?? d.mappings
        calibration = try c.decodeIfPresent(CalibrationProfile.self, forKey: .calibration)
        showToast = try c.decodeIfPresent(Bool.self, forKey: .showToast) ?? d.showToast
        onboardingStep = try c.decodeIfPresent(OnboardingStep.self, forKey: .onboardingStep) ?? d.onboardingStep
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? d.onboardingCompleted
    }

    public func action(for gesture: Gesture) -> GestureAction {
        mappings.first { $0.gesture == gesture }?.action ?? .none
    }

    public mutating func setAction(_ action: GestureAction, for gesture: Gesture) {
        if let i = mappings.firstIndex(where: { $0.gesture == gesture }) {
            mappings[i].action = action
        } else {
            mappings.append(.init(gesture: gesture, action: action))
        }
    }

    /// The classifier configuration these settings imply.
    public func classifierConfig() -> ClassifierConfig {
        var config = ClassifierConfig()
        config.cooldown = Double(cooldownMs) / 1000
        let factor = min(max(sensitivity, Settings.sensitivityRange.lowerBound), Settings.sensitivityRange.upperBound)
        return (calibration?.apply(to: config) ?? config).scaled(angle: factor)
    }
}
