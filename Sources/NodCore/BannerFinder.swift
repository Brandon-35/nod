import Foundation

/// A node of the Accessibility tree as plain values, so finding banners is testable without a screen.
/// `ref` indexes the live element kept by the real backend.
public struct AXNode: Equatable, Sendable {
    public var ref = 0
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var description: String?
    public var actions: [String] = []
    public var children: [AXNode] = []

    public init(ref: Int = 0, role: String? = nil, subrole: String? = nil, title: String? = nil,
                description: String? = nil, actions: [String] = [], children: [AXNode] = []) {
        self.ref = ref
        self.role = role
        self.subrole = subrole
        self.title = title
        self.description = description
        self.actions = actions
        self.children = children
    }
}

/// What the real Accessibility backend acts on for one banner or alert in NotificationCenter.
public struct FoundBanner: Equatable, Sendable {
    public var ref: Int
    public var isAlert: Bool
    /// The stock dismiss action on the banner itself (`Name:Close…`), never an app-defined "Close"/"Clear".
    public var closeAction: String?
    public var acceptButtonRef: Int?
    public var declineButtonRef: Int?
    public var isCall: Bool { acceptButtonRef != nil && declineButtonRef != nil }
}

/// Finds banners in the NotificationCenter tree. Banner subroles and the stock Close action name were found
/// by a sibling project on real notifications; they are the same here but still need an on-device check.
/// Button titles are matched in English only: a localized macOS may not match (known limit).
public enum BannerFinder {
    public static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    static let acceptTitles: Set<String> = ["accept", "answer"]
    static let declineTitles: Set<String> = ["decline"]

    public static func banners(in root: AXNode) -> [FoundBanner] {
        if let subrole = root.subrole, bannerSubroles.contains(subrole) { return [parse(root)] }
        return root.children.flatMap(banners(in:))
    }

    private static func parse(_ node: AXNode) -> FoundBanner {
        let isAlert = node.subrole == "AXNotificationCenterAlert"
        var found = FoundBanner(ref: node.ref, isAlert: isAlert,
                                closeAction: isAlert ? nil : node.actions.first { $0.hasPrefix("Name:Close\n") })
        scanButtons(node, into: &found)
        return found
    }

    private static func scanButtons(_ node: AXNode, into found: inout FoundBanner) {
        if node.role == "AXButton" {
            let label = (node.title ?? node.description ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if found.acceptButtonRef == nil, acceptTitles.contains(label) { found.acceptButtonRef = node.ref }
            if found.declineButtonRef == nil, declineTitles.contains(label) { found.declineButtonRef = node.ref }
        }
        for child in node.children { scanButtons(child, into: &found) }
    }
}
