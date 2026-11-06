import Foundation
import Testing
@testable import NodCore

@Suite struct OnboardingFlowTests {
    @Test func happyPathVisitsEveryStepInOrder() {
        var flow = OnboardingFlow()
        var seen: [OnboardingStep] = [flow.step]
        func note() { if seen.last != flow.step { seen.append(flow.step) } }
        flow.continueTapped(); note()
        flow.motionAuthorizationChanged(.authorized); note()
        flow.headphonesWornChanged(true); note()
        flow.calibrationFinished(success: true); note()
        flow.continueTapped(); note()
        flow.continueTapped()
        #expect(seen == OnboardingStep.allCases)
        #expect(flow.isFinished)
    }

    @Test func deniedMotionStaysOnStepWithFixPanel() {
        var flow = OnboardingFlow()
        flow.continueTapped()
        flow.motionAuthorizationChanged(.denied)
        #expect(flow.step == .motion && flow.motionDenied)
        flow.motionAuthorizationChanged(.authorized) // person fixed it in System Settings
        #expect(flow.step == .airpods && !flow.motionDenied)
    }

    @Test func alreadyAuthorizedSkipsTheMotionWait() {
        var flow = OnboardingFlow(motion: .authorized)
        flow.continueTapped()
        #expect(flow.step == .airpods)
    }

    @Test func stallsAfterTenSecondsAndRecoversWhenWorn() {
        var flow = OnboardingFlow(resumeAt: .airpods, motion: .authorized)
        flow.waited(9)
        #expect(flow.airpods == .waiting)
        flow.waited(10)
        #expect(flow.airpods == .stalled)
        flow.headphonesWornChanged(true)
        #expect(flow.step == .calibration && flow.airpods == .connected)
    }

    @Test func failedCalibrationAsksToRetryAndSkipUsesDefaults() {
        var flow = OnboardingFlow(resumeAt: .calibration, motion: .authorized)
        flow.calibrationFinished(success: false)
        #expect(flow.step == .calibration && flow.calibration == .retryNeeded)
        flow.skipCalibration()
        #expect(flow.step == .assign && flow.calibration == .skipped)
    }

    @Test func eventsOutOfStepAreIgnored() {
        var flow = OnboardingFlow()
        flow.headphonesWornChanged(true)
        flow.calibrationFinished(success: true)
        flow.skipCalibration()
        #expect(flow.step == .welcome)
    }

    @Test func resumesFromStoredStep() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try store.update { $0.onboardingStep = .calibration }
        let again = SettingsStore(directory: dir).settings
        #expect(OnboardingFlow(resumeAt: again.onboardingStep).step == .calibration)
        #expect(!again.onboardingCompleted)
    }
}

@Suite struct CalibrationSessionTests {
    func run(_ samples: [MotionSample]) -> CalibrationSession {
        var s = CalibrationSession()
        for sample in samples { s.add(sample) }
        return s
    }

    @Test func gesturesMarkTheirMetersAnyOrder() {
        let s = run(SyntheticMotion.sequence([.shake, .nod, .tiltRight, .tiltLeft]))
        #expect(s.meters.values.allSatisfy { $0 == .gotIt })
        #expect(s.current == nil)
    }

    @Test func nothingHappeningTurnsCapturingIntoRetry() {
        let s = run(SyntheticMotion.take(.still, seed: 1, seconds: 8).samples)
        #expect(s.meters[.nod] == .retry)
        #expect(s.meters[.shake] == .idle)
    }

    @Test func fullRunGivesAProfile() throws {
        let s = run(SyntheticMotion.sequence([.nod, .shake, .tiltLeft, .tiltRight], gap: 0.3))
        #expect(s.isFinished)
        _ = try s.result().get()
    }
}
