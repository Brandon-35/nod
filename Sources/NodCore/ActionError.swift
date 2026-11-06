import Foundation

/// Why an action did not run. Every case carries a message the person can act on; nothing is swallowed.
public enum ActionError: Error, Equatable, Sendable {
    case accessibilityNotGranted
    case noNotification
    /// The banner stays on screen: macOS gives apps no public way to close persistent alerts.
    case cannotDismiss
    case noCall
    case shortcutNotFound(String)
    case shortcutFailed(name: String, detail: String)
    case invalidShortcutName
    case notSupported(String)

    /// Text for the status line and the Settings error row.
    public var message: String {
        switch self {
        case .accessibilityNotGranted:
            "Nod needs Accessibility permission to do this. Open System Settings > Privacy & Security > Accessibility and turn Nod on."
        case .noNotification: "There is no notification on screen to act on."
        case .cannotDismiss: "This notification is an alert that stays until you act on it, so Nod cannot close it."
        case .noCall: "There is no incoming FaceTime call to answer or decline."
        case .shortcutNotFound(let name): "No Shortcut named \"\(name)\". Check the name in the Shortcuts app."
        case .shortcutFailed(let name, let detail): "The Shortcut \"\(name)\" failed: \(detail)"
        case .invalidShortcutName: "Pick a Shortcut name in Settings."
        case .notSupported(let what): "\(what) is not supported on this Mac."
        }
    }
}
