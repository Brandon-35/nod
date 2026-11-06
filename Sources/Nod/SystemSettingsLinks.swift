import AppKit

/// Deep links into System Settings > Privacy & Security.
enum SystemSettingsLinks {
    static let motion = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @MainActor static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}
