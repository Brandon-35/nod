import Foundation
import Testing
@testable import NodCore

/// All data here is synthetic (SyntheticMotion). It shows the classifier logic works; it does not show
/// accuracy on a real head.
func gestures(in take: FixtureFile.Take, config: ClassifierConfig = ClassifierConfig()) -> [Gesture] {
    var classifier = GestureClassifier(config: config)
    return take.samples.compactMap { classifier.process($0) }
}

@Suite struct GestureClassifierTests {
    @Test(arguments: SyntheticMotion.Kind.allCases.filter(\.isGesture))
    func recallOnSyntheticGestures(kind: SyntheticMotion.Kind) {
        let expected = Gesture(rawValue: kind.rawValue)!
        let hits = (1...20).filter { gestures(in: SyntheticMotion.take(kind, seed: UInt64($0))) == [expected] }
        #expect(hits.count >= 18, "\(kind): \(hits.count)/20 exact")
    }

    @Test(arguments: [SyntheticMotion.Kind.still, .musicNod, .lookAside, .talking])
    func noFalsePositiveOnSyntheticNoise(kind: SyntheticMotion.Kind) {
        for seed in 1...20 {
            let take = SyntheticMotion.take(kind, seed: UInt64(seed), seconds: kind == .musicNod ? 10 : 6)
            #expect(gestures(in: take).isEmpty, "\(kind) seed \(seed)")
        }
    }

    @Test func cooldownBlocksSecondHitFromSameMovement() {
        var config = ClassifierConfig()
        config.cooldown = 5
        let a = SyntheticMotion.take(.nod, seed: 2, seconds: 3).samples
        let b = SyntheticMotion.take(.nod, seed: 3, seconds: 3, start: a.last!.t + 0.3).samples
        var classifier = GestureClassifier(config: config)
        #expect((a + b).compactMap { classifier.process($0) }.count == 1)
    }

    @Test func twoSeparateNodsAfterCooldownBothCount() {
        let a = SyntheticMotion.take(.nod, seed: 2, seconds: 3).samples
        let b = SyntheticMotion.take(.nod, seed: 3, seconds: 3, start: a.last!.t + 2).samples
        var classifier = GestureClassifier()
        #expect((a + b).compactMap { classifier.process($0) } == [.nod, .nod])
    }

    @Test func burstGapStartsFreshWindow() {
        // First half of a nod, a 2 s silence, then the rest: must not join into one gesture.
        let take = SyntheticMotion.take(.nod, seed: 4).samples
        let mid = take.count / 2
        let late = take[mid...].map { var s = $0; s.t += 2; return s }
        var classifier = GestureClassifier()
        let hits = (Array(take[..<mid]) + late).compactMap { classifier.process($0) }
        #expect(hits.count <= 1)
    }

    @Test func outOfOrderSampleIsIgnored() {
        var classifier = GestureClassifier()
        _ = classifier.process(MotionSample(t: 10, pitch: 0, yaw: 0, roll: 0))
        #expect(classifier.process(MotionSample(t: 9, pitch: 1, yaw: 0, roll: 0)) == nil)
    }

    @Test func largerThresholdsRejectSmallGesture() {
        var strict = ClassifierConfig()
        strict.minPitchRange = 5
        #expect(gestures(in: SyntheticMotion.take(.nod, seed: 1), config: strict).isEmpty)
    }
}
