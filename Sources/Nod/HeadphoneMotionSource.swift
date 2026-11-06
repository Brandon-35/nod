import CoreMotion
import Foundation
import NodCore

/// Reads head motion from AirPods through the public `CMHeadphoneMotionManager`. Data only
/// arrives while the AirPods are worn. CoreMotion calls back on the main queue given to `start`.
final class HeadphoneMotionSource: NSObject, MotionSource, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    let events: AsyncStream<MotionEvent>
    private let continuation: AsyncStream<MotionEvent>.Continuation
    private let manager = CMHeadphoneMotionManager()

    override init() {
        (events, continuation) = AsyncStream.makeStream(of: MotionEvent.self, bufferingPolicy: .bufferingNewest(256))
        super.init()
    }

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        // The delegate goes first, or a connect event can slip past.
        manager.delegate = self
        manager.startDeviceMotionUpdates(to: .main) { [continuation] motion, _ in
            guard let motion else { return }
            // Copy the plain numbers before anything crosses an isolation boundary.
            continuation.yield(.sample(MotionSample(
                t: motion.timestamp,
                pitch: motion.attitude.pitch, yaw: motion.attitude.yaw, roll: motion.attitude.roll,
                rotX: motion.rotationRate.x, rotY: motion.rotationRate.y, rotZ: motion.rotationRate.z)))
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.delegate = nil
        continuation.finish()
    }

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        continuation.yield(.connected)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        continuation.yield(.disconnected)
    }
}

extension HeadphoneMotionSource {
    /// Current Motion permission as the engine understands it.
    static func authorization() -> MotionAuthorization {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: .authorized
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }
}
