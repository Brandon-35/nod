import AppKit
import NodCore
import Observation

/// Owns the long-lived objects. `NOD_SIMULATED_ONLY=1` swaps the AirPods and the system backends for fakes, so the
/// whole app runs on a Mac without AirPods or permissions.
@MainActor @Observable final class AppModel {
    let store: SettingsStore
    /// Observable mirror of the store, so views redraw. Change settings through `update`.
    private(set) var settings: Settings
    let engine: GestureEngine
    let permissions: SystemPermissions
    let simulated: Bool
    @ObservationIgnored private let source: MotionSource
    @ObservationIgnored private var ticker: Timer?

    init(simulated: Bool = ProcessInfo.processInfo.environment["NOD_SIMULATED_ONLY"] == "1") {
        self.simulated = simulated
        let override = ProcessInfo.processInfo.environment["NOD_SETTINGS_DIR"]
        let store = SettingsStore(directory: override.map { URL(fileURLWithPath: $0, isDirectory: true) })
        self.store = store
        settings = store.settings
        let permissions = SystemPermissions()
        self.permissions = permissions
        if simulated {
            let fake = FakeActionBackends()
            fake.isNotificationVisible = true
            source = FakeMotionSource(samples: SyntheticMotion.sequence([.nod, .shake, .tiltLeft]))
            engine = GestureEngine(source: source, store: store, runner: fake.dispatcher(), watcher: fake, permissions: fake,
                                   uptime: { 0 })
        } else {
            let real = HeadphoneMotionSource()
            let keyboard = SystemKeyboard()
            let notifications = AXNotificationBackend()
            source = real
            let dispatcher = ActionDispatcher(media: keyboard, keys: keyboard, shortcuts: ShortcutsCLI(),
                                              notifications: notifications, permissions: permissions)
            engine = GestureEngine(source: real, store: store, runner: dispatcher, watcher: notifications, permissions: permissions,
                                   motionAuthorization: { HeadphoneMotionSource.authorization() },
                                   motionAvailable: { real.isAvailable }, mediaPlaying: { AudioActivity.isOutputRunning() })
        }
    }

    func motionAuthorization() -> MotionAuthorization { simulated ? .authorized : HeadphoneMotionSource.authorization() }

    func start() {
        engine.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [engine] _ in
            MainActor.assumeIsolated { engine.tick() }
        }
    }

    func stop() {
        ticker?.invalidate()
        engine.stop()
    }

    func update(_ change: (inout Settings) -> Void) {
        try? store.update(change)
        settings = store.settings
    }

    var listenMode: ListeningMode {
        get { settings.listenMode }
        set { update { $0.listenMode = newValue } }
    }
}
