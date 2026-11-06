import Foundation
import Testing
@testable import NodCore

func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("nod-test-\(UUID().uuidString)", isDirectory: true)
}

@Suite struct SettingsStoreTests {
    @Test func defaultsMatchTheDecision() {
        let s = Settings()
        #expect(s.listenMode == .onlyWhenNotification)
        #expect(s.action(for: .nod) == .dismissNotification)
        #expect(s.action(for: .shake) == .nextTrack)
        #expect(s.action(for: .tiltRight) == .none)
        #expect(s.schemaVersion == 1)
    }

    @Test func roundTripsThroughDisk() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try store.update {
            $0.listenMode = .always
            $0.setAction(.runShortcut("Focus"), for: .tiltRight)
            $0.setAction(.keyboardShortcut(KeyCombo(keyCode: 36, command: true)), for: .shake)
        }
        let again = SettingsStore(directory: dir).settings
        #expect(again == store.settings)
        #expect(again.action(for: .tiltRight) == .runShortcut("Focus"))
        #expect(again.action(for: .shake) == .keyboardShortcut(KeyCombo(keyCode: 36, command: true)))
    }

    @Test func mappingCanBeChangedAndSameActionAllowedTwice() throws {
        var s = Settings()
        s.setAction(.playPause, for: .nod)
        s.setAction(.playPause, for: .shake)
        #expect(s.action(for: .nod) == .playPause && s.action(for: .shake) == .playPause)
    }

    @Test func v0FileMigratesToV1() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"mode":"always","cooldownMs":1200}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        let store = SettingsStore(directory: dir)
        #expect(store.loadIssue == nil)
        #expect(store.settings.listenMode == .always)
        #expect(store.settings.cooldownMs == 1200)
        #expect(store.settings.schemaVersion == 1)
        #expect(store.settings.action(for: .nod) == .dismissNotification)
    }

    @Test func corruptFileIsKeptUntilFirstSave() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try Data("not json".utf8).write(to: file)
        let store = SettingsStore(directory: dir)
        #expect(store.loadIssue == .corrupt)
        #expect(store.settings == Settings())
        #expect(try String(contentsOf: file, encoding: .utf8) == "not json")
        try store.update { $0.armGesture = .shake }
        #expect(store.loadIssue == nil)
        #expect(try String(contentsOf: dir.appendingPathComponent("settings.unreadable-1.json"), encoding: .utf8) == "not json")
    }

    @Test func newerVersionIsNotOverwrittenSilently() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
        #expect(SettingsStore(directory: dir).loadIssue == .newerVersion(99))
    }

    @Test func sensitivityIsClampedAndScalesThresholds() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try store.update { $0.sensitivity = 50 }
        #expect(store.settings.sensitivity == 2.0)
        #expect(store.settings.classifierConfig().minPitchRange == ClassifierConfig().minPitchRange * 2)
    }

    @Test func resetRestoresDefaults() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)
        try store.update { $0.listenMode = .always }
        try store.reset()
        #expect(store.settings == Settings())
        #expect(SettingsStore(directory: dir).settings == Settings())
    }
}
