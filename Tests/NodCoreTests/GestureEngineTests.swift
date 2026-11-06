import Foundation
import Testing
@testable import NodCore

@MainActor @Suite struct GestureEngineTests {
    struct Rig {
        var engine: GestureEngine
        var fake: FakeActionBackends
        var dir: URL
    }

    func rig(_ take: FixtureFile.Take, mode: ListeningMode = .onlyWhenNotification, notification: Bool = true,
             accessibility: Bool = true, motion: MotionAuthorization = .authorized, paused: Bool = false) throws -> Rig {
        let dir = tempDir()
        let store = SettingsStore(directory: dir)
        try store.update { $0.listenMode = mode }
        let fake = FakeActionBackends()
        fake.isNotificationVisible = notification
        fake.accessibilityGranted = accessibility
        let engine = GestureEngine(source: FakeMotionSource(take: take), store: store, runner: fake.dispatcher(), watcher: fake,
                                   permissions: fake, motionAuthorization: { motion }, uptime: { 0 })
        engine.isPaused = paused
        return Rig(engine: engine, fake: fake, dir: dir)
    }

    @Test func nodWithNotificationDismissesIt() async throws {
        let r = try rig(SyntheticMotion.take(.nod, seed: 1)); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.engine.start()
        await r.engine.finish()
        #expect(r.fake.calls == ["dismiss"])
        #expect(r.engine.lastEvent?.gesture == .nod && r.engine.lastEvent?.outcome == .ran)
        #expect(r.engine.status == .listening)
    }

    @Test func nodWithoutNotificationIsIgnoredInDefaultMode() async throws {
        let r = try rig(SyntheticMotion.take(.nod, seed: 1), notification: false); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.engine.start()
        await r.engine.finish()
        #expect(r.fake.calls.isEmpty)
        #expect(r.engine.lastEvent?.outcome == .ignored(.nothingToActOn))
    }

    @Test func shakeInAlwaysModeSkipsTrack() async throws {
        let r = try rig(SyntheticMotion.take(.shake, seed: 2), mode: .always, notification: false); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.engine.start()
        await r.engine.finish()
        #expect(r.fake.calls == ["nextTrack"])
    }

    @Test func pausedEngineRunsNothingAndSaysPaused() async throws {
        let r = try rig(SyntheticMotion.take(.nod, seed: 1), paused: true); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.engine.start()
        await r.engine.finish()
        #expect(r.fake.calls.isEmpty && r.engine.lastEvent == nil)
        #expect(r.engine.status == .paused)
    }

    @Test func missingAccessibilityShowsErrorAndStatus() async throws {
        let r = try rig(SyntheticMotion.take(.nod, seed: 1), accessibility: false); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.engine.start()
        await r.engine.finish()
        #expect(r.fake.calls.isEmpty)
        #expect(r.engine.lastEvent?.outcome == .failed(.accessibilityNotGranted))
        #expect(r.engine.status == .accessibilityMissing)
    }

    @Test func deniedMotionBeatsEverything() throws {
        let r = try rig(SyntheticMotion.take(.still, seed: 1), accessibility: false, motion: .denied, paused: true); defer { try? FileManager.default.removeItem(at: r.dir) }
        #expect(r.engine.status == .motionDenied)
    }

    @Test func statusFollowsWornSignal() throws {
        let r = try rig(SyntheticMotion.take(.still, seed: 1)); defer { try? FileManager.default.removeItem(at: r.dir) }
        #expect(r.engine.status == .notWorn)
        r.engine.handle(.connected)
        #expect(r.engine.status == .listening)
        r.engine.handle(.disconnected)
        #expect(r.engine.status == .notWorn)
    }

    @Test func noMotionHardwareMeansNoAirPods() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeActionBackends()
        let engine = GestureEngine(source: FakeMotionSource([]), store: SettingsStore(directory: dir), runner: fake.dispatcher(),
                                   watcher: fake, permissions: fake, motionAvailable: { false })
        #expect(engine.status == .noAirPods)
    }

    @Test func noiseRunsNothing() async throws {
        for kind in [SyntheticMotion.Kind.musicNod, .lookAside, .talking, .still] {
            let r = try rig(SyntheticMotion.take(kind, seed: 3, seconds: 8), mode: .always); defer { try? FileManager.default.removeItem(at: r.dir) }
            r.engine.start()
            await r.engine.finish()
            #expect(r.fake.calls.isEmpty, "\(kind)")
        }
    }
}

@MainActor @Suite struct SimulatedSequenceTests {
    @Test func sequenceRunsThreeActionsInOrder() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let fake = FakeActionBackends()
        fake.isNotificationVisible = true
        let engine = GestureEngine(source: FakeMotionSource(samples: SyntheticMotion.sequence([.nod, .shake, .tiltLeft])),
                                   store: SettingsStore(directory: dir), runner: fake.dispatcher(), watcher: fake, permissions: fake, uptime: { 0 })
        engine.start()
        await engine.finish()
        #expect(fake.calls == ["dismiss", "nextTrack", "playPause"])
    }
}
