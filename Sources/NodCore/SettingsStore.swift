import Foundation

/// Loads and saves `Settings` as JSON in Application Support. One writer lock, atomic writes.
/// A file that cannot be read (corrupt, or written by a newer app) is never overwritten silently: the app runs
/// on defaults, and the first save moves the old file aside as `settings.unreadable-<n>.json`.
public final class SettingsStore: @unchecked Sendable {
    public enum LoadIssue: Error, Equatable, Sendable { case corrupt, newerVersion(Int) }

    public let url: URL
    public private(set) var loadIssue: LoadIssue?
    private var current: Settings
    private let lock = NSLock()

    /// `directory` defaults to `~/Library/Application Support/Nod`.
    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nod", isDirectory: true)
        url = dir.appendingPathComponent("settings.json")
        current = Settings()
        if let data = try? Data(contentsOf: url) {
            switch Self.decode(data) {
            case .success(let settings): current = settings
            case .failure(let issue): loadIssue = issue
            }
        }
    }

    public var settings: Settings {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Applies `change` and saves. Throws when the file cannot be written; the in-memory value still changes.
    public func update(_ change: (inout Settings) -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        change(&current)
        current.sensitivity = min(max(current.sensitivity, Settings.sensitivityRange.lowerBound), Settings.sensitivityRange.upperBound)
        try save()
    }

    /// Back to defaults ("Delete all settings").
    public func reset() throws {
        lock.lock(); defer { lock.unlock() }
        current = Settings()
        try save()
    }

    private func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if loadIssue != nil, fm.fileExists(atPath: url.path) {
            var n = 1
            var aside = url.deletingLastPathComponent().appendingPathComponent("settings.unreadable-1.json")
            while fm.fileExists(atPath: aside.path) {
                n += 1
                aside = url.deletingLastPathComponent().appendingPathComponent("settings.unreadable-\(n).json")
            }
            try fm.moveItem(at: url, to: aside)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(current).write(to: url, options: .atomic)
        loadIssue = nil
    }

    // MARK: Decoding and migration

    static func decode(_ data: Data) -> Result<Settings, LoadIssue> {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure(.corrupt) }
        let version = object["schemaVersion"] as? Int ?? 0
        if version > Settings.currentSchemaVersion { return .failure(.newerVersion(version)) }
        if version < 1 { migrateV0(&object) }
        guard let migrated = try? JSONSerialization.data(withJSONObject: object) else { return .failure(.corrupt) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let settings = try? decoder.decode(Settings.self, from: migrated) else { return .failure(.corrupt) }
        return .success(settings)
    }

    /// v0 (pre-release drafts) called the listening mode `mode` and had no schemaVersion; unknown values fall back to the default.
    private static func migrateV0(_ object: inout [String: Any]) {
        if let old = object.removeValue(forKey: "mode") as? String {
            let map = ["notification": "onlyWhenNotification", "arm": "armWithDoubleGesture", "always": "always"]
            if let new = map[old] { object["listenMode"] = new }
        }
        object["schemaVersion"] = 1
    }
}
