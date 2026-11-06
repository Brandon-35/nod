import Foundation
import Testing
@testable import NodCore

/// One test per state in design/screen-inventory.md S-10 to S-14, S-12 and S-30.
@MainActor @Suite struct StatusPresentationTests {
    func engine(motion: MotionAuthorization = .authorized, available: Bool = true, unsupported: Bool = false,
                accessibility: Bool = true, mappings: [GestureMapping]? = nil) -> GestureEngine {
        let fake = FakeActionBackends()
        fake.accessibilityGranted = accessibility
        let store = SettingsStore(directory: tempDir())
        if let mappings { try? store.update { $0.mappings = mappings } }
        return GestureEngine(source: FakeMotionSource([]), store: store, runner: fake.dispatcher(), watcher: fake, permissions: fake,
                             motionAuthorization: { motion }, motionAvailable: { available }, headphonesUnsupported: { unsupported },
                             uptime: { 0 })
    }

    @Test func noAirPodsS11() {
        let m = engine(available: false).status.message
        #expect(engine(available: false).status == .noAirPods)
        #expect(m.detail == "No AirPods connected. Connect your AirPods to use gestures." && m.fix == nil)
    }

    @Test func notWornS13() {
        let e = engine()
        #expect(e.status == .notWorn)
        #expect(e.status.message.detail == "Your AirPods aren't in your ears. Put them in to start.")
    }

    @Test func unsupportedHeadphonesS14() {
        let e = engine(unsupported: true)
        #expect(e.status == .unsupportedHeadphones)
        #expect(e.status.message.detail == "These headphones don't have motion sensors, so Nod can't read head gestures.")
    }

    @Test func motionDeniedS12OpensTheMotionPane() {
        let e = engine(motion: .denied, unsupported: true)
        #expect(e.status == .motionDenied) // a missing permission beats every other state
        #expect(e.status.message.fix == .openMotionSettings)
    }

    @Test func accessibilityMissingS12OnlyWhenAMappingNeedsIt() {
        let needs = engine(accessibility: false)
        #expect(needs.status == .accessibilityMissing && needs.status.message.fix == .openAccessibilitySettings)
        let none = engine(accessibility: false, mappings: Gesture.allCases.map { GestureMapping(gesture: $0, action: .none) })
        #expect(none.status != .accessibilityMissing)
    }

    func event(_ outcome: GestureEvent.Outcome, _ action: GestureAction = .dismissNotification) -> GestureEvent {
        GestureEvent(gesture: .nod, action: action, outcome: outcome, at: 0)
    }

    @Test func toastRecognisedS30() {
        #expect(ToastContent(event: event(.ran), enabled: true)?.text == "Nod: dismissed notification")
        #expect(ToastContent(event: event(.ran, .runShortcut("Focus")), enabled: true)?.text == "Nod: ran Focus")
    }

    @Test func toastErrorVariantHasAFixForAccessibilityOnly() {
        let a = ToastContent(event: event(.failed(.accessibilityNotGranted)), enabled: true)
        #expect(a?.isError == true && a?.fix == .openAccessibilitySettings && a?.text.hasPrefix("That action couldn't run.") == true)
        let b = ToastContent(event: event(.failed(.noNotification)), enabled: true)
        #expect(b?.isError == true && b?.fix == nil)
    }

    @Test func noToastWhenOffIgnoredOrUnmapped() {
        #expect(ToastContent(event: event(.ran), enabled: false) == nil)
        #expect(ToastContent(event: event(.ignored(.nothingToActOn)), enabled: true) == nil)
        #expect(ToastContent(event: event(.ran, .none), enabled: true) == nil)
    }

    @Test func toastSettingDefaultsOnAndSurvivesOldFiles() throws {
        #expect(Settings().showToast)
        let old = Data(#"{"schemaVersion":1}"#.utf8)
        #expect(try JSONDecoder().decode(Settings.self, from: old).showToast)
    }
}
