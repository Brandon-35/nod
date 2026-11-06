import Foundation
import NodCore

/// Non-UI modes of the executable. Returns true when an argument was handled and the app must not start.
enum NodCommand {
    static var recordingsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nod/recordings", isDirectory: true)
    }

    /// `--record <label> <seconds>` writes a take from the AirPods; `--gen-fixtures <dir>` writes synthetic takes.
    static func handle(_ args: [String]) -> Bool {
        guard args.count >= 2 else { return false }
        switch args[1] {
        case "--record":
            guard args.count >= 4, let seconds = Double(args[3]), seconds > 0 else {
                FileHandle.standardError.write(Data("usage: Nod --record <label> <seconds>\n".utf8))
                exit(2)
            }
            record(label: args[2], seconds: seconds)
            return true
        case "--simulate":
            simulate()
            return true
        case "--gen-fixtures":
            guard args.count >= 3 else { exit(2) }
            generate(into: URL(fileURLWithPath: args[2], isDirectory: true))
            return true
        default:
            return false
        }
    }

    /// Runs the whole chain (fake motion, engine, gate, fake actions) and prints one line per gesture. No AirPods needed.
    private static func simulate() {
        Task { @MainActor in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nod-simulate-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let fake = FakeActionBackends()
            fake.isNotificationVisible = true
            let engine = GestureEngine(source: FakeMotionSource(samples: SyntheticMotion.sequence([.nod, .shake, .tiltLeft])),
                                       store: SettingsStore(directory: dir), runner: fake.dispatcher(), watcher: fake,
                                       permissions: fake, uptime: { 0 })
            engine.start()
            await engine.finish()
            print("simulate: actions \(fake.calls.joined(separator: ","))")
            exit(fake.calls.isEmpty ? 1 : 0)
        }
        dispatchMain()
    }

    private static func record(label: String, seconds: Double) {
        let source = HeadphoneMotionSource()
        guard source.isAvailable else {
            FileHandle.standardError.write(Data("No headphone motion available. Wear your AirPods and run from Nod.app.\n".utf8))
            exit(1)
        }
        // Seconds of slack before giving up when no sample ever arrives (AirPods not worn).
        let timeout = Task { try await Task.sleep(for: .seconds(seconds + 15)); print("no samples: are the AirPods worn?"); exit(1) }
        Task {
            let take = await Recorder.record(from: source, label: label, seconds: seconds)
            timeout.cancel()
            do {
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let file = recordingsDirectory.appendingPathComponent("\(label)-\(stamp).jsonl")
                try FixtureFile.encode(take).write(to: file)
                print("\(take.samples.count) samples -> \(file.path)")
                exit(0)
            } catch {
                print("write failed: \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func generate(into dir: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for kind in SyntheticMotion.Kind.allCases {
                let take = SyntheticMotion.take(kind, seed: 1)
                try FixtureFile.encode(take).write(to: dir.appendingPathComponent("\(kind.rawValue)-seed1.jsonl"))
            }
            print("wrote \(SyntheticMotion.Kind.allCases.count) fixtures to \(dir.path)")
        } catch {
            print("failed: \(error)")
            exit(1)
        }
    }
}
