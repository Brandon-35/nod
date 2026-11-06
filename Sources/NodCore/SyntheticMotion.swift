import Foundation

/// Deterministic synthetic head motion for tests and fixtures. NOT real head data: results measured on it
/// say nothing about accuracy on a person wearing AirPods.
///
/// Sample timing is bursty like the probe (2026-11-06): ~60 Hz while moving, ~5 Hz while still.
/// Sign conventions for roll are an assumption until the on-device recordings confirm them.
public enum SyntheticMotion {
    public enum Kind: String, CaseIterable, Sendable {
        case nod, shake, tiltLeft, tiltRight
        case still, musicNod, lookAside, talking
        public var isGesture: Bool { [.nod, .shake, .tiltLeft, .tiltRight].contains(self) }
    }

    /// Small deterministic generator so the same seed always gives the same take.
    struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
    }

    /// A take of `kind` lasting about `seconds`, starting at device time `start`.
    /// Gesture takes put one gesture in the middle with still head before and after.
    public static func take(_ kind: Kind, seed: UInt64, seconds: Double = 4, start: Double = 1000,
                            amplitudeScale: Double = 1) -> FixtureFile.Take {
        var rng = Rng(state: seed &* 2654435761 &+ 1)
        let restPitch = rng.range(-0.1, 0.1), restYaw = rng.range(-0.3, 0.3), restRoll = rng.range(-0.05, 0.05)
        let amplitude = rng.range(0.9, 1.4) * amplitudeScale // person-to-person size of the movement
        let speed = rng.range(0.85, 1.2) // person-to-person tempo
        let moveStart = seconds * 0.4

        // Offsets from rest at time u (seconds since take start): (pitch, yaw, roll).
        func offset(_ u: Double) -> (Double, Double, Double) {
            switch kind {
            case .nod:
                // Two nods (head down and back up), 0.45 s each.
                let d = 0.45 / speed, v = u - moveStart
                guard v >= 0, v < 2 * d else { return (0, 0, 0) }
                return (0.42 * amplitude * abs(sin(.pi * v / d)), 0, 0)
            case .shake:
                let d = 0.9 / speed, v = u - moveStart // two full left-right swings
                guard v >= 0, v < d else { return (0, 0, 0) }
                return (0, 0.5 * amplitude * sin(4 * .pi * v / d), 0)
            case .tiltLeft, .tiltRight:
                let d = 0.9 / speed, v = u - moveStart // lean over and come back, two swings
                guard v >= 0, v < d else { return (0, 0, 0) }
                let dir = kind == .tiltLeft ? -1.0 : 1.0
                return (0, 0, dir * 0.42 * amplitude * abs(sin(2 * .pi * v / d)))
            case .still:
                return (0, 0, 0)
            case .musicNod:
                // Small continuous bobbing at about 2 Hz for the whole take.
                return (0.07 * amplitude * sin(2 * .pi * 2 * u), 0, 0)
            case .lookAside:
                // Slow turn to a second screen, hold, turn back: 1.4 s each way.
                let v = u - moveStart
                guard v >= 0, v < 4.2 else { return (0, 0, 0) }
                let ramp = min(v, 4.2 - v, 1.4) / 1.4
                return (0, 0.7 * ramp, 0)
            case .talking:
                return (0.03 * sin(2 * .pi * 3 * u) * amplitude, 0.04 * sin(2 * .pi * 1.3 * u), 0)
            }
        }

        var samples: [MotionSample] = []
        var u = 0.0
        var prev = offset(0)
        while u < seconds {
            let o = offset(u)
            let moving = abs(o.0) + abs(o.1) + abs(o.2) > 0.01 || u >= moveStart - 0.1 && u <= moveStart + 4.5 && kind != .still
            let dt = moving ? 1 / 60.0 : 1 / 5.0
            let noise = { rng.range(-0.004, 0.004) }
            samples.append(MotionSample(
                t: start + u,
                pitch: restPitch + o.0 + noise(), yaw: restYaw + o.1 + noise(), roll: restRoll + o.2 + noise(),
                rotX: (o.0 - prev.0) / dt, rotY: (o.1 - prev.1) / dt, rotZ: (o.2 - prev.2) / dt))
            prev = o
            u += dt
        }
        return FixtureFile.Take(label: kind.rawValue, samples: samples)
    }

    /// Takes with seeds 1...count for each requested kind.
    public static func suite(_ kinds: [Kind] = Kind.allCases, count: Int = 20, seconds: Double = 4) -> [FixtureFile.Take] {
        kinds.flatMap { kind in (1...count).map { take(kind, seed: UInt64($0), seconds: kind == .musicNod ? 10 : seconds) } }
    }

    /// One continuous stream: a take of each kind in order, `gap` seconds of stillness between them.
    public static func sequence(_ kinds: [Kind], seed: UInt64 = 1, gap: Double = 2) -> [MotionSample] {
        var out: [MotionSample] = []
        var start = 1000.0
        for kind in kinds {
            let samples = take(kind, seed: seed, start: start).samples
            out += samples
            start = (samples.last?.t ?? start) + gap
        }
        return out
    }
}
