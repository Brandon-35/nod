import Foundation

/// Replays a fixed list of events, for tests and for running the app without AirPods.
/// Events are delivered immediately and in order; the stream finishes after the last one.
public final class FakeMotionSource: MotionSource {
    public let events: AsyncStream<MotionEvent>
    private let continuation: AsyncStream<MotionEvent>.Continuation
    private let script: [MotionEvent]

    public init(_ script: [MotionEvent]) {
        self.script = script
        (events, continuation) = AsyncStream.makeStream(of: MotionEvent.self, bufferingPolicy: .unbounded)
    }

    public convenience init(samples: [MotionSample]) {
        self.init([.connected] + samples.map(MotionEvent.sample))
    }

    public func start() {
        for event in script { continuation.yield(event) }
        continuation.finish()
    }

    public func stop() { continuation.finish() }
}
