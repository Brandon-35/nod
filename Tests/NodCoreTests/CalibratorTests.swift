import Foundation
import Testing
@testable import NodCore

/// A 10 s calibration run: a nod take, then a shake take, both at the given amplitude scale. Synthetic data.
func calibrationRun(scale: Double, seed: UInt64 = 1) -> [MotionSample] {
    let nod = SyntheticMotion.take(.nod, seed: seed, seconds: 5, start: 0, amplitudeScale: scale).samples
    let shake = SyntheticMotion.take(.shake, seed: seed, seconds: 5.2, start: nod.last!.t + 0.2, amplitudeScale: scale).samples
    return nod + shake
}

func calibrate(_ samples: [MotionSample]) -> Result<CalibrationProfile, CalibrationError> {
    var c = Calibrator()
    for s in samples { c.add(s) }
    return c.result()
}

@Suite struct CalibratorTests {
    @Test func smallAndLargeMovementsGiveDifferentThresholdsWithinLimits() throws {
        let small = try calibrate(calibrationRun(scale: 0.7)).get()
        let large = try calibrate(calibrationRun(scale: 1.6)).get()
        #expect(small.pitchFactor < large.pitchFactor)
        #expect(small.yawFactor < large.yawFactor)
        for f in [small.pitchFactor, small.yawFactor, large.pitchFactor, large.yawFactor] {
            #expect(CalibrationProfile.factorRange.contains(f))
        }
    }

    @Test func extremeAmplitudeIsClamped() throws {
        let huge = try calibrate(calibrationRun(scale: 8)).get()
        #expect(huge.pitchFactor == CalibrationProfile.factorRange.upperBound)
    }

    @Test func barelyMovingHeadFailsAndKeepsDefaults() {
        #expect(calibrate(SyntheticMotion.take(.still, seed: 1, seconds: 10).samples) == .failure(.insufficientMovement))
        #expect(calibrate(calibrationRun(scale: 0.1)) == .failure(.insufficientMovement))
        #expect(calibrate([]) == .failure(.insufficientMovement))
    }

    @Test func finishesAfterTenSeconds() {
        var c = Calibrator()
        let still = SyntheticMotion.take(.still, seed: 1, seconds: 12).samples
        for s in still where !c.isFinished { c.add(s) }
        #expect(c.isFinished)
        #expect(c.elapsed >= 10)
    }

    @Test func calibratedClassifierCatchesAGestureTheDefaultsMiss() throws {
        // A person who nods small: 0.5 scale is below the default pitch threshold.
        let small = SyntheticMotion.take(.nod, seed: 2, amplitudeScale: 0.6)
        #expect(gestures(in: small).isEmpty)
        let profile = try calibrate(calibrationRun(scale: 0.8)).get()
        var settings = Settings()
        settings.calibration = profile
        #expect(gestures(in: small, config: settings.classifierConfig()) == [.nod])
    }

    @Test func profilePersistsAndResets() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        let profile = try calibrate(calibrationRun(scale: 1.2)).get()
        try store.update { $0.calibration = profile }
        let loaded = SettingsStore(directory: dir).settings.calibration
        #expect(loaded?.pitchFactor == profile.pitchFactor)
        try store.update { $0.calibration = nil }
        #expect(SettingsStore(directory: dir).settings.calibration == nil)
        #expect(SettingsStore(directory: dir).settings.classifierConfig() == Settings().classifierConfig())
    }

    @Test func calibratedConfigNeverLeavesTheSafeBand() throws {
        let profile = try calibrate(calibrationRun(scale: 8)).get()
        let base = ClassifierConfig()
        let c = profile.apply(to: base)
        #expect(c.minPitchRange <= base.minPitchRange * 1.6 + 1e-9)
        #expect(c.minPitchRange >= base.minPitchRange * 0.6 - 1e-9)
    }
}
