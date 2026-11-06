import Foundation
import Observation

public enum MotionAuthorization: Sendable, Equatable {
    case notDetermined, authorized, denied
}

/// What the engine did with a gesture, for the toast and the status line (S-30, S-12).
public struct GestureEvent: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case ran
        case ignored(IgnoreReason)
        case failed(ActionError)
    }
    public var gesture: Gesture
    public var action: GestureAction
    public var outcome: Outcome
    /// Device-clock time of the sample that completed the gesture.
    public var at: TimeInterval
}

/// Connects motion, classifier, listening gate and actions, and exposes the state the menu bar shows.
/// All inputs are injected, so the whole chain runs in tests and in `--simulate` with fakes.
@MainActor @Observable public final class GestureEngine {
    public enum Status: Sendable, Equatable {
        case listening, paused, notWorn, noAirPods, unsupportedHeadphones, motionDenied, accessibilityMissing
    }

    public private(set) var lastEvent: GestureEvent?
    public private(set) var isWorn = false
    public var isPaused = false
    /// Sees every raw sample before the worn and pause checks. Onboarding calibration listens here.
    @ObservationIgnored public var sampleTap: (@MainActor (MotionSample) -> Void)?

    @ObservationIgnored private let source: MotionSource
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let runner: ActionRunner
    @ObservationIgnored private let watcher: NotificationWatching
    @ObservationIgnored private let permissions: PermissionChecking
    @ObservationIgnored private let motionAuthorization: @MainActor () -> MotionAuthorization
    @ObservationIgnored private let motionAvailable: @MainActor () -> Bool
    @ObservationIgnored private let headphonesUnsupported: @MainActor () -> Bool
    @ObservationIgnored private let mediaPlaying: @MainActor () -> Bool
    @ObservationIgnored private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored private var worn: WornTracker
    @ObservationIgnored private var classifier = GestureClassifier()
    @ObservationIgnored private var gate = ListeningGate()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pending: [Task<Void, Never>] = []

    public init(source: MotionSource, store: SettingsStore, runner: ActionRunner, watcher: NotificationWatching,
                permissions: PermissionChecking,
                motionAuthorization: @escaping @MainActor () -> MotionAuthorization = { .authorized },
                motionAvailable: @escaping @MainActor () -> Bool = { true },
                headphonesUnsupported: @escaping @MainActor () -> Bool = { false },
                mediaPlaying: @escaping @MainActor () -> Bool = { false },
                uptime: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                staleAfter: TimeInterval? = WornTracker.defaultStaleAfter) {
        self.source = source
        self.store = store
        self.runner = runner
        self.watcher = watcher
        self.permissions = permissions
        self.motionAuthorization = motionAuthorization
        self.motionAvailable = motionAvailable
        self.headphonesUnsupported = headphonesUnsupported
        self.mediaPlaying = mediaPlaying
        self.uptime = uptime
        self.worn = WornTracker(staleAfter: staleAfter)
    }

    /// Menu bar state. Order matters: a missing permission beats everything, a pause beats the headphone state.
    public var status: Status {
        if motionAuthorization() == .denied { return .motionDenied }
        if !permissions.accessibilityGranted, store.settings.mappings.contains(where: { $0.action.needsAccessibility }) {
            return .accessibilityMissing
        }
        if headphonesUnsupported() { return .unsupportedHeadphones }
        if isPaused { return .paused }
        if !motionAvailable() { return .noAirPods }
        return isWorn ? .listening : .notWorn
    }

    /// Starts reading the source until it ends or `stop()` is called.
    public func start() {
        guard loop == nil else { return }
        let events = source.events
        source.start()
        loop = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    public func stop() {
        source.stop()
        loop?.cancel()
        loop = nil
    }

    /// Waits for the source to end and every started action to finish. For tests and `--simulate`.
    public func finish() async {
        await loop?.value
        for task in pending { await task.value }
        pending.removeAll()
    }

    /// Call about once a second so a silent stream eventually reads as "not worn".
    public func tick() {
        worn.tick(now: uptime())
        isWorn = worn.isWorn
    }

    public func handle(_ event: MotionEvent) {
        let now: TimeInterval
        if case .sample(let s) = event { now = s.t } else { now = uptime() }
        worn.handle(event, now: now)
        isWorn = worn.isWorn
        if case .disconnected = event {
            classifier.reset()
            gate.reset()
        }
        if case .sample(let raw) = event { sampleTap?(raw) }
        guard case .sample(let sample) = event, worn.isWorn, !isPaused else { return }
        let settings = store.settings
        classifier.config = settings.classifierConfig()
        guard let gesture = classifier.process(sample) else { return }
        let context = ListeningContext(now: sample.t, notificationVisible: watcher.isNotificationVisible, mediaPlaying: mediaPlaying())
        let action = settings.action(for: gesture)
        switch gate.decide(gesture, settings: settings, context: context) {
        case .ignore(let reason):
            lastEvent = GestureEvent(gesture: gesture, action: action, outcome: .ignored(reason), at: sample.t)
        case .run(let action):
            let task = Task { [runner] in
                let outcome: GestureEvent.Outcome
                do { try await runner.run(action); outcome = .ran } catch let error as ActionError { outcome = .failed(error) }
                catch { outcome = .failed(.notSupported("This action")) }
                self.lastEvent = GestureEvent(gesture: gesture, action: action, outcome: outcome, at: sample.t)
            }
            pending.append(task)
        }
    }
}
