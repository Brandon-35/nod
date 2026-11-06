import Foundation

/// The four v1 gestures.
public enum Gesture: String, Sendable, Codable, CaseIterable, Equatable {
    case nod, shake, tiltLeft, tiltRight
}
