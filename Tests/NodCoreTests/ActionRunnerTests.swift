import Foundation
import Testing
@testable import NodCore

@MainActor @Suite struct ActionRunnerTests {
    @Test func eachActionReachesItsBackend() async throws {
        let fake = FakeActionBackends()
        let d = fake.dispatcher()
        try await d.run(.playPause)
        try await d.run(.nextTrack)
        try await d.run(.previousTrack)
        try await d.run(.keyboardShortcut(KeyCombo(keyCode: 49, command: true)))
        try await d.run(.runShortcut("  Focus mode "))
        try await d.run(.dismissNotification)
        try await d.run(.snoozeNotification)
        try await d.run(.answerFaceTime)
        try await d.run(.declineFaceTime)
        try await d.run(.none)
        #expect(fake.calls == ["playPause", "nextTrack", "previousTrack", "key:49", "shortcut:Focus mode", "dismiss", "dismiss", "answer", "decline"])
    }

    @Test func missingAccessibilityIsAFixableErrorAndNothingRuns() async {
        let fake = FakeActionBackends()
        fake.accessibilityGranted = false
        let d = fake.dispatcher()
        for action: GestureAction in [.playPause, .nextTrack, .previousTrack, .dismissNotification, .answerFaceTime, .declineFaceTime,
                                      .keyboardShortcut(KeyCombo(keyCode: 1))] {
            await #expect(throws: ActionError.accessibilityNotGranted) { try await d.run(action) }
        }
        #expect(fake.calls.isEmpty)
        #expect(ActionError.accessibilityNotGranted.message.contains("Accessibility"))
    }

    @Test func shortcutDoesNotNeedAccessibility() async throws {
        let fake = FakeActionBackends()
        fake.accessibilityGranted = false
        try await fake.dispatcher().run(.runShortcut("Focus"))
        #expect(fake.calls == ["shortcut:Focus"])
    }

    @Test func blankShortcutNameIsRejected() async {
        let fake = FakeActionBackends()
        await #expect(throws: ActionError.invalidShortcutName) { try await fake.dispatcher().run(.runShortcut("   ")) }
        #expect(fake.calls.isEmpty)
    }

    @Test func backendErrorsPropagateWithActionableMessage() async {
        let fake = FakeActionBackends()
        fake.failure = .noNotification
        await #expect(throws: ActionError.noNotification) { try await fake.dispatcher().run(.dismissNotification) }
        #expect(!ActionError.shortcutNotFound("X").message.isEmpty)
        #expect(ActionError.cannotDismiss.message.contains("alert"))
    }
}

@Suite struct BannerFinderTests {
    func banner(subrole: String, actions: [String] = [], buttons: [(String, Int)] = [], ref: Int = 1) -> AXNode {
        AXNode(ref: ref, role: "AXGroup", subrole: subrole, actions: actions,
               children: buttons.map { AXNode(ref: $0.1, role: "AXButton", title: $0.0) })
    }

    @Test func findsBannerAndStockCloseAction() {
        let root = AXNode(ref: 0, role: "AXWindow", children: [banner(subrole: "AXNotificationCenterBanner", actions: ["Name:Close\nTarget:0x0", "AXPress"])])
        let found = BannerFinder.banners(in: root)
        #expect(found.count == 1)
        #expect(found[0].closeAction == "Name:Close\nTarget:0x0")
        #expect(!found[0].isAlert)
    }

    @Test func appDefinedCloseIsNeverUsed() {
        let root = banner(subrole: "AXNotificationCenterBanner", actions: ["Name:Clear\nTarget:0x0", "Name:Close All"])
        #expect(BannerFinder.banners(in: root)[0].closeAction == nil)
    }

    @Test func persistentAlertCannotBeClosed() {
        let root = banner(subrole: "AXNotificationCenterAlert", actions: ["Name:Close\nTarget:0x0"])
        let found = BannerFinder.banners(in: root)[0]
        #expect(found.isAlert && found.closeAction == nil)
    }

    @Test func faceTimeCallHasAcceptAndDecline() {
        let root = banner(subrole: "AXNotificationCenterAlert", buttons: [("Decline", 7), ("Accept", 8)])
        let found = BannerFinder.banners(in: root)[0]
        #expect(found.isCall && found.acceptButtonRef == 8 && found.declineButtonRef == 7)
    }

    @Test func plainBannerIsNotACall() {
        #expect(!BannerFinder.banners(in: banner(subrole: "AXNotificationCenterBanner", buttons: [("Reply", 3)]))[0].isCall)
    }

    @Test func emptyTreeHasNoBanners() {
        #expect(BannerFinder.banners(in: AXNode(role: "AXWindow")).isEmpty)
    }
}
