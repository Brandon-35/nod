import Foundation
import Testing
@testable import NodCore

@Suite struct ListeningGateTests {
    func settings(_ mode: ListeningMode) -> Settings {
        var s = Settings()
        s.listenMode = mode
        s.setAction(.runShortcut("Focus"), for: .tiltRight)
        return s
    }

    /// Full table for the default mode: action x (notification, media) -> runs?
    @Test(arguments: [
        (GestureAction.dismissNotification, false, false, false),
        (.dismissNotification, true, false, true),
        (.dismissNotification, false, true, false),
        (.snoozeNotification, false, true, false),
        (.answerFaceTime, true, false, true),
        (.declineFaceTime, false, true, false),
        (.playPause, false, false, false),
        (.playPause, false, true, true),
        (.playPause, true, false, true),
        (.nextTrack, false, true, true),
        (.nextTrack, false, false, false),
        (.previousTrack, false, true, true),
        (.previousTrack, false, false, false),
        (.keyboardShortcut(KeyCombo(keyCode: 36)), false, true, false),
        (.keyboardShortcut(KeyCombo(keyCode: 36)), true, false, true),
        (.runShortcut("Focus"), false, true, false),
        (.runShortcut("Focus"), true, true, true),
        (.none, true, true, false),
    ])
    func defaultModeTable(action: GestureAction, notification: Bool, media: Bool, runs: Bool) {
        var s = settings(.onlyWhenNotification)
        s.setAction(action, for: .nod)
        var gate = ListeningGate()
        let decision = gate.decide(.nod, settings: s, context: ListeningContext(now: 1, notificationVisible: notification, mediaPlaying: media))
        #expect(decision == (runs ? .run(action) : .ignore(action == .none ? .unassigned : .nothingToActOn)))
    }

    @Test func alwaysModeRunsAnyAssignedAction() {
        var gate = ListeningGate()
        let s = settings(.always)
        #expect(gate.decide(.tiltRight, settings: s, context: ListeningContext(now: 0)) == .run(.runShortcut("Focus")))
        #expect(gate.decide(.shake, settings: s, context: ListeningContext(now: 1)) == .run(.nextTrack))
        var none = s
        none.setAction(.none, for: .shake)
        #expect(gate.decide(.shake, settings: none, context: ListeningContext(now: 2)) == .ignore(.unassigned))
    }

    @Test func armedModeNeedsDoubleGestureThenRunsOnce() {
        var gate = ListeningGate()
        let s = settings(.armWithDoubleGesture) // arm gesture defaults to nod
        func ctx(_ t: Double) -> ListeningContext { ListeningContext(now: t) }
        #expect(gate.decide(.shake, settings: s, context: ctx(0)) == .ignore(.notArmed))
        #expect(gate.decide(.nod, settings: s, context: ctx(1)) == .ignore(.notArmed))
        #expect(gate.decide(.nod, settings: s, context: ctx(2)) == .ignore(.notArmed)) // armed now, arming nod swallowed
        #expect(gate.isArmed(at: 2.1))
        #expect(gate.decide(.shake, settings: s, context: ctx(3)) == .run(.nextTrack))
        #expect(!gate.isArmed(at: 3.1))
        #expect(gate.decide(.shake, settings: s, context: ctx(4)) == .ignore(.notArmed))
    }

    @Test func slowSecondGestureDoesNotArm() {
        var gate = ListeningGate()
        let s = settings(.armWithDoubleGesture)
        _ = gate.decide(.nod, settings: s, context: ListeningContext(now: 0))
        _ = gate.decide(.nod, settings: s, context: ListeningContext(now: 2)) // beyond 1.5 s: starts a new first
        #expect(!gate.isArmed(at: 2.1))
        #expect(gate.decide(.shake, settings: s, context: ListeningContext(now: 3)) == .ignore(.notArmed))
    }

    @Test func armingExpires() {
        var gate = ListeningGate()
        let s = settings(.armWithDoubleGesture)
        _ = gate.decide(.nod, settings: s, context: ListeningContext(now: 0))
        _ = gate.decide(.nod, settings: s, context: ListeningContext(now: 1))
        #expect(gate.decide(.shake, settings: s, context: ListeningContext(now: 7)) == .ignore(.notArmed))
    }

    /// Nodding along to music, no notification: the default mode runs nothing. Synthetic data.
    @Test func noddingToMusicWithoutNotificationRunsNothing() {
        let s = settings(.onlyWhenNotification)
        var classifier = GestureClassifier(config: s.classifierConfig())
        var gate = ListeningGate()
        var ran: [GestureAction] = []
        // A deliberate nod while music plays and no notification is showing, and a real nod during a notification.
        let nod1 = SyntheticMotion.take(.nod, seed: 3, seconds: 3, start: 0).samples
        let nod2 = SyntheticMotion.take(.nod, seed: 4, seconds: 3, start: 10).samples
        for sample in nod1 + nod2 {
            guard let g = classifier.process(sample) else { continue }
            let ctx = ListeningContext(now: sample.t, notificationVisible: sample.t > 9, mediaPlaying: false)
            if case .run(let a) = gate.decide(g, settings: s, context: ctx) { ran.append(a) }
        }
        #expect(ran == [.dismissNotification])
    }
}
