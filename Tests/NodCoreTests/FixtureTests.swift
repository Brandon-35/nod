import Foundation
import Testing
@testable import NodCore

@Suite struct FixtureTests {
    @Test func roundTripKeepsEverySample() throws {
        let take = SyntheticMotion.take(.nod, seed: 3)
        let back = try FixtureFile.decode(FixtureFile.encode(take))
        #expect(back == take)
    }

    @Test func badLineIsReported() {
        #expect(throws: FixtureFile.DecodeError.badLine(2)) {
            try FixtureFile.decode(Data("{\"label\":\"a\",\"t\":1,\"pitch\":0,\"yaw\":0,\"roll\":0,\"rotX\":0,\"rotY\":0,\"rotZ\":0}\nnope\n".utf8))
        }
    }

    @Test func syntheticIsDeterministicAndBursty() {
        #expect(SyntheticMotion.take(.shake, seed: 5) == SyntheticMotion.take(.shake, seed: 5))
        #expect(SyntheticMotion.take(.shake, seed: 5) != SyntheticMotion.take(.shake, seed: 6))
        let s = SyntheticMotion.take(.nod, seed: 1).samples
        let gaps = zip(s, s.dropFirst()).map { $1.t - $0.t }
        #expect(gaps.contains { $0 < 0.02 } && gaps.contains { $0 > 0.15 })
    }

    @Test func recorderStopsAfterRequestedSpan() async {
        let take = SyntheticMotion.take(.still, seed: 1, seconds: 10)
        let recorded = await Recorder.record(from: FakeMotionSource(take: take), label: "still", seconds: 2)
        #expect(recorded.label == "still")
        let span = recorded.samples.last!.t - recorded.samples.first!.t
        #expect(span <= 2 && span > 1.7)
    }

    @Test func committedFixturesLoad() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/synthetic")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
        #expect(files.count == SyntheticMotion.Kind.allCases.count)
        for file in files {
            let take = try FixtureFile.decode(Data(contentsOf: file))
            #expect(!take.samples.isEmpty && file.lastPathComponent.hasPrefix(take.label))
        }
    }
}
