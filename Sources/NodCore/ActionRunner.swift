import Foundation

/// Backends the dispatcher calls. The real ones live in the Nod target; the `Fake…` ones record calls for tests
/// and for running the app without AirPods or permissions. All main-actor: they touch AppKit or Accessibility.
@MainActor public protocol MediaControlling: AnyObject {
    func playPause() throws
    func nextTrack() throws
    func previousTrack() throws
    func volumeUp() throws
    func volumeDown() throws
    func toggleMute() throws
}

@MainActor public protocol KeySending: AnyObject {
    func send(_ combo: KeyCombo) throws
}

@MainActor public protocol ShortcutRunning: AnyObject {
    func run(name: String) async throws
}

@MainActor public protocol NotificationControlling: AnyObject {
    func dismiss() throws
    func answerCall() throws
    func declineCall() throws
}

/// "Is a notification on screen?" for the listening gate.
@MainActor public protocol NotificationWatching: AnyObject {
    var isNotificationVisible: Bool { get }
}

@MainActor public protocol PermissionChecking: AnyObject {
    var accessibilityGranted: Bool { get }
}

@MainActor public protocol ActionRunner: AnyObject {
    func run(_ action: GestureAction) async throws
}

/// Maps a `GestureAction` to the backend that performs it, and refuses (with a fixable error) when a permission is missing.
@MainActor public final class ActionDispatcher: ActionRunner {
    let media: MediaControlling
    let keys: KeySending
    let shortcuts: ShortcutRunning
    let notifications: NotificationControlling
    let permissions: PermissionChecking

    public init(media: MediaControlling, keys: KeySending, shortcuts: ShortcutRunning,
                notifications: NotificationControlling, permissions: PermissionChecking) {
        self.media = media
        self.keys = keys
        self.shortcuts = shortcuts
        self.notifications = notifications
        self.permissions = permissions
    }

    public func run(_ action: GestureAction) async throws {
        switch action {
        case .none:
            return
        case .playPause:
            try requireAccessibility()
            try media.playPause()
        case .nextTrack:
            try requireAccessibility()
            try media.nextTrack()
        case .previousTrack:
            try requireAccessibility()
            try media.previousTrack()
        case .volumeUp:
            try requireAccessibility()
            try media.volumeUp()
        case .volumeDown:
            try requireAccessibility()
            try media.volumeDown()
        case .toggleMute:
            try requireAccessibility()
            try media.toggleMute()
        case .screenshot:
            try requireAccessibility()
            try keys.send(KeyCombo(keyCode: 20, command: true, shift: true)) // Command-Shift-3
        case .missionControl:
            try requireAccessibility()
            try keys.send(KeyCombo(keyCode: 126, control: true)) // Control-Up Arrow
        case .keyboardShortcut(let combo):
            try requireAccessibility()
            try keys.send(combo)
        case .runShortcut(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 200, !trimmed.contains("\0") else { throw ActionError.invalidShortcutName }
            try await shortcuts.run(name: trimmed)
        case .dismissNotification, .snoozeNotification:
            // macOS has no public snooze: both close the banner, which stays in Notification Center.
            try requireAccessibility()
            try notifications.dismiss()
        case .answerFaceTime:
            try requireAccessibility()
            try notifications.answerCall()
        case .declineFaceTime:
            try requireAccessibility()
            try notifications.declineCall()
        }
    }

    private func requireAccessibility() throws {
        guard permissions.accessibilityGranted else { throw ActionError.accessibilityNotGranted }
    }
}

// MARK: Fakes

/// Records every call. One object stands in for all backends.
@MainActor public final class FakeActionBackends: MediaControlling, KeySending, ShortcutRunning, NotificationControlling,
                                                  NotificationWatching, PermissionChecking {
    public var calls: [String] = []
    public var accessibilityGranted = true
    public var isNotificationVisible = false
    /// When set, the next backend call throws it.
    public var failure: ActionError?
    public init() {}

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { self.failure = nil; throw failure }
    }

    public func playPause() throws { try record("playPause") }
    public func nextTrack() throws { try record("nextTrack") }
    public func previousTrack() throws { try record("previousTrack") }
    public func volumeUp() throws { try record("volumeUp") }
    public func volumeDown() throws { try record("volumeDown") }
    public func toggleMute() throws { try record("toggleMute") }
    public func send(_ combo: KeyCombo) throws { try record("key:\(combo.keyCode)") }
    public func run(name: String) async throws { try record("shortcut:\(name)") }
    public func dismiss() throws { try record("dismiss") }
    public func answerCall() throws { try record("answer") }
    public func declineCall() throws { try record("decline") }

    public func dispatcher() -> ActionDispatcher {
        ActionDispatcher(media: self, keys: self, shortcuts: self, notifications: self, permissions: self)
    }
}
