import Foundation

/// JSONL fixture format shared by the recorder, `FakeMotionSource` and the tests. One line per sample:
/// the `MotionSample` fields plus the `label` of the take. Documented in Tests/NodCoreTests/Fixtures/README.md.
public enum FixtureFile {
    struct Line: Codable {
        var label: String
        var t: Double, pitch: Double, yaw: Double, roll: Double
        var rotX: Double, rotY: Double, rotZ: Double
    }

    public struct Take: Sendable, Equatable {
        public var label: String
        public var samples: [MotionSample]
        public init(label: String, samples: [MotionSample]) {
            self.label = label
            self.samples = samples
        }
    }

    public enum DecodeError: Error, Equatable { case badLine(Int), mixedLabels }

    public static func encode(_ take: Take) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var out = Data()
        for s in take.samples {
            let line = Line(label: take.label, t: s.t, pitch: s.pitch, yaw: s.yaw, roll: s.roll,
                            rotX: s.rotX, rotY: s.rotY, rotZ: s.rotZ)
            out.append(try encoder.encode(line))
            out.append(0x0A)
        }
        return out
    }

    public static func decode(_ data: Data) throws -> Take {
        let decoder = JSONDecoder()
        var label: String?
        var samples: [MotionSample] = []
        for (index, raw) in data.split(separator: 0x0A, omittingEmptySubsequences: true).enumerated() {
            guard let line = try? decoder.decode(Line.self, from: Data(raw)) else { throw DecodeError.badLine(index + 1) }
            if let label, label != line.label { throw DecodeError.mixedLabels }
            label = line.label
            samples.append(MotionSample(t: line.t, pitch: line.pitch, yaw: line.yaw, roll: line.roll,
                                        rotX: line.rotX, rotY: line.rotY, rotZ: line.rotZ))
        }
        return Take(label: label ?? "", samples: samples)
    }
}

public extension FakeMotionSource {
    /// Replays a recorded or synthetic take.
    convenience init(take: FixtureFile.Take) { self.init(samples: take.samples) }
}

/// Collects samples from a source for a fixed span of device time.
public enum Recorder {
    /// Reads `source` until `seconds` of sample time have passed since the first sample, or the stream ends.
    public static func record(from source: MotionSource, label: String, seconds: Double) async -> FixtureFile.Take {
        var samples: [MotionSample] = []
        source.start()
        for await event in source.events {
            guard case .sample(let s) = event else { continue }
            if let first = samples.first, s.t - first.t > seconds { break }
            samples.append(s)
        }
        source.stop()
        return FixtureFile.Take(label: label, samples: samples)
    }
}
