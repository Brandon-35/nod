import AppKit
import ApplicationServices
import NodCore

// Real backends for the action dispatcher. Compiled and unit-tested through fakes only: they have not run
// against real notifications, media players or FaceTime.

@MainActor final class SystemPermissions: PermissionChecking {
    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once; call only after the person clicked a button.
    func requestAccessibility() {
        // The documented value of kAXTrustedCheckOptionPrompt; the constant is a mutable global that Swift 6 rejects.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Media keys and arbitrary key combos, sent as HID events (need Accessibility).
@MainActor final class SystemKeyboard: MediaControlling, KeySending {
    private static let playKey: Int32 = 16 // NX_KEYTYPE_PLAY
    private static let nextKey: Int32 = 17 // NX_KEYTYPE_NEXT
    private static let previousKey: Int32 = 18 // NX_KEYTYPE_PREVIOUS

    func playPause() throws { Self.postMediaKey(Self.playKey) }
    func nextTrack() throws { Self.postMediaKey(Self.nextKey) }
    func previousTrack() throws { Self.postMediaKey(Self.previousKey) }

    func send(_ combo: KeyCombo) throws {
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        if combo.shift { flags.insert(.maskShift) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: combo.keyCode, keyDown: down) else {
                throw ActionError.notSupported("Sending keys")
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postMediaKey(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: Int((key << 16) | (state << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// `shortcuts run <name>` without a shell: the name is one argument, so quotes and spaces are safe.
@MainActor final class ShortcutsCLI: ShortcutRunning {
    func run(name: String) async throws {
        let result = try await Self.execute(["run", name])
        guard result.status != 0 else { return }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.localizedCaseInsensitiveContains("couldn't find") || detail.localizedCaseInsensitiveContains("not found") {
            throw ActionError.shortcutNotFound(name)
        }
        throw ActionError.shortcutFailed(name: name, detail: detail.isEmpty ? "exit status \(result.status)" : detail)
    }

    private nonisolated static func execute(_ arguments: [String]) async throws -> (status: Int32, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            let err = Pipe()
            process.standardError = err
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { p in
                let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (p.terminationStatus, text))
            }
            do { try process.run() } catch { continuation.resume(throwing: ActionError.notSupported("The Shortcuts command")) }
            // shortcut: no timeout, a hung Shortcut keeps its process; add one if on-device runs show hangs.
        }
    }
}

/// Reads and acts on NotificationCenter banners through Accessibility.
@MainActor final class AXNotificationBackend: NotificationControlling, NotificationWatching {
    private static let bundleID = "com.apple.notificationcenterui"

    private struct Scan {
        var banners: [FoundBanner] = []
        var elements: [AXUIElement] = []
    }

    var isNotificationVisible: Bool {
        AXIsProcessTrusted() && !scan().banners.isEmpty
    }

    func dismiss() throws {
        let scan = try requireScan()
        guard let banner = scan.banners.first(where: { !$0.isCall }) ?? scan.banners.first else { throw ActionError.noNotification }
        guard let action = banner.closeAction else { throw ActionError.cannotDismiss }
        guard AXUIElementPerformAction(scan.elements[banner.ref], action as CFString) == .success else { throw ActionError.cannotDismiss }
    }

    func answerCall() throws { try press(\.acceptButtonRef) }
    func declineCall() throws { try press(\.declineButtonRef) }

    private func press(_ button: KeyPath<FoundBanner, Int?>) throws {
        let scan = try requireScan()
        guard let call = scan.banners.first(where: \.isCall), let ref = call[keyPath: button] else { throw ActionError.noCall }
        guard AXUIElementPerformAction(scan.elements[ref], kAXPressAction as CFString) == .success else { throw ActionError.noCall }
    }

    private func requireScan() throws -> Scan {
        guard AXIsProcessTrusted() else { throw ActionError.accessibilityNotGranted }
        let result = scan()
        guard !result.banners.isEmpty else { throw ActionError.noNotification }
        return result
    }

    private func scan() -> Scan {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return Scan() }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var elements: [AXUIElement] = []
        let tree = AXNode(ref: -1, children: children(of: root).map { node(for: $0, depth: 0, elements: &elements) })
        return Scan(banners: BannerFinder.banners(in: tree), elements: elements)
    }

    private func node(for element: AXUIElement, depth: Int, elements: inout [AXUIElement]) -> AXNode {
        var node = AXNode(ref: elements.count, role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute),
                          title: string(element, kAXTitleAttribute), description: string(element, kAXDescriptionAttribute))
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        node.actions = (names as? [String]) ?? []
        elements.append(element)
        guard depth < 8, elements.count < 200 else { return node }
        node.children = children(of: element).map { self.node(for: $0, depth: depth + 1, elements: &elements) }
        return node
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let attribute = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard attribute == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
