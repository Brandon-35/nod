import Foundation
import Testing
@testable import NodCore

/// Deterministic bursty stream: 60 Hz while moving, 5 Hz while still, with optional gaps.
func burstySamples() -> [MotionSample] {
    var out: [MotionSample] = []
    var t = 100.0
    func segment(seconds: Double, hz: Double, amplitude: Double) {
        let end = t + seconds
        while t < end {
            out.append(MotionSample(t: t, pitch: amplitude * sin(t * 9), yaw: 0, roll: 0))
            t += 1 / hz
        }
    }
    segment(seconds: 2, hz: 60, amplitude: 0.3)
    segment(seconds: 5, hz: 5, amplitude: 0)
    t += 2.5 // gap with no samples at all
    segment(seconds: 1, hz: 70, amplitude: 0.3)
    return out
}

@Suite struct MotionSourceTests {
    @Test func fakeSourceReplaysInOrderThenFinishes() async {
        let samples = burstySamples()
        let source = FakeMotionSource(samples: samples)
        source.start()
        var got: [MotionEvent] = []
        for await event in source.events { got.append(event) }
        #expect(got.first == .connected)
        #expect(got.count == samples.count + 1)
        #expect(got.dropFirst().map { if case .sample(let s) = $0 { s.t } else { -1 } } == samples.map(\.t))
    }

    @Test func burstyStreamHasUnevenRates() {
        let samples = burstySamples()
        let gaps = zip(samples, samples.dropFirst()).map { $1.t - $0.t }
        #expect(gaps.min()! < 0.02)
        #expect(gaps.max()! > 2.0)
    }

    @Test func stillHeadAndShortGapStayWorn() {
        var tracker = WornTracker()
        for sample in burstySamples() {
            tracker.handle(.sample(sample), now: sample.t)
            tracker.tick(now: sample.t)
            #expect(tracker.isWorn)
        }
    }

    @Test func disconnectEndsWornAndSampleRestoresIt() {
        var tracker = WornTracker()
        tracker.handle(.connected, now: 0)
        #expect(tracker.isWorn)
        tracker.handle(.disconnected, now: 1)
        #expect(!tracker.isWorn)
        tracker.handle(.sample(MotionSample(t: 2, pitch: 0, yaw: 0, roll: 0)), now: 2)
        #expect(tracker.isWorn)
    }

    @Test func silenceBeyondStaleAfterExpiresWorn() {
        var tracker = WornTracker(staleAfter: 30)
        tracker.handle(.connected, now: 0)
        tracker.tick(now: 29)
        #expect(tracker.isWorn)
        tracker.tick(now: 31)
        #expect(!tracker.isWorn)
    }

    @Test func nilStaleAfterNeverExpires() {
        var tracker = WornTracker(staleAfter: nil)
        tracker.handle(.connected, now: 0)
        tracker.tick(now: 100_000)
        #expect(tracker.isWorn)
    }
}
