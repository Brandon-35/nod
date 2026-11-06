import Foundation
import Testing
@testable import NodCore

/// End to end on SYNTHETIC data: fixture file -> FakeMotionSource -> classifier -> gate -> fake action.
/// Nothing here is measured on a head wearing AirPods; accuracy on people stays an on-device question.
@MainActor @Suite struct IntegrationTests {
    static let fixtureDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/synthetic")

    func run(_ take: FixtureFile.Take, mode: ListeningMode, notification: Bool) async throws -> [String] {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try store.update { $0.listenMode = mode }
        let fake = FakeActionBackends()
        fake.isNotificationVisible = notification
        let engine = GestureEngine(source: FakeMotionSource(take: take), store: store, runner: fake.dispatcher(), watcher: fake,
                                   permissions: fake, uptime: { 0 })
        engine.start()
        await engine.finish()
        return fake.calls
    }

    func committed(_ kind: SyntheticMotion.Kind) throws -> FixtureFile.Take {
        try FixtureFile.decode(Data(contentsOf: Self.fixtureDir.appendingPathComponent("\(kind.rawValue)-seed1.jsonl")))
    }

    @Test func committedGestureFixturesRunTheirDefaultAction() async throws {
        let expected: [SyntheticMotion.Kind: [String]] = [.nod: ["dismiss"], .shake: ["nextTrack"], .tiltLeft: ["playPause"], .tiltRight: []]
        for (kind, calls) in expected {
            #expect(try await run(committed(kind), mode: .always, notification: true) == calls, "\(kind)")
        }
    }

    @Test func committedNoiseFixturesRunNothingInAnyMode() async throws {
        for kind in SyntheticMotion.Kind.allCases where !kind.isGesture {
            for mode in ListeningMode.allCases {
                #expect(try await run(committed(kind), mode: mode, notification: true).isEmpty, "\(kind) \(mode)")
            }
        }
    }

    @Test func gestureWithNothingToActOnIsHeldBackByTheGate() async throws {
        #expect(try await run(committed(.nod), mode: .onlyWhenNotification, notification: false).isEmpty)
        #expect(try await run(committed(.nod), mode: .onlyWhenNotification, notification: true) == ["dismiss"])
    }

    @Test func twentySeedSweepHitsEveryGestureAndNeverFiresOnNoise() async throws {
        var hits = 0, total = 0, noiseRuns = 0
        for take in SyntheticMotion.suite(count: 20) {
            let kind = SyntheticMotion.Kind(rawValue: take.label)!
            let calls = try await run(take, mode: .always, notification: true)
            if kind.isGesture {
                guard kind != .tiltRight else { continue }
                total += 1
                if calls.count == 1 { hits += 1 }
            } else {
                noiseRuns += calls.count
            }
        }
        print("integration sweep (synthetic): \(hits)/\(total) gestures ran exactly one action, \(noiseRuns) actions on noise takes")
        #expect(hits == total)
        #expect(noiseRuns == 0)
    }
}
