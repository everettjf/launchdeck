import AppKit
import XCTest
@testable import LaunchDeck

@MainActor
final class ClipboardAndSnippetTests: XCTestCase {
    func testClipboardDeduplicatesLimitsExpiresAndClears() {
        let suite = "ClipboardStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ClipboardStore(fileURL: fileURL, legacyDefaults: defaults, maximumCount: 2)
        let now = Date()
        store.record("old", retentionHours: 24, now: now.addingTimeInterval(-90_000))
        store.record("one", retentionHours: 24, now: now)
        store.record("one", retentionHours: 24, now: now)
        store.record("two", retentionHours: 24, now: now)
        XCTAssertEqual(store.entries.map(\.text), ["two", "one"])
        store.flush()
        let reloaded = ClipboardStore(fileURL: fileURL, legacyDefaults: defaults, maximumCount: 2)
        XCTAssertEqual(reloaded.entries.map(\.text), ["two", "one"])
        store.clear()
        store.flush()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testClipboardMigratesLegacyDefaultsAndRemovesThem() throws {
        let suite = "ClipboardMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        defaults.set(try JSONEncoder().encode([ClipboardEntry(text: "legacy")]), forKey: ClipboardStore.legacyDefaultsKey)
        let store = ClipboardStore(fileURL: fileURL, legacyDefaults: defaults)
        XCTAssertEqual(store.entries.map(\.text), ["legacy"])
        XCTAssertNil(defaults.data(forKey: ClipboardStore.legacyDefaultsKey))
        store.flush()
        XCTAssertEqual(ClipboardStore(fileURL: fileURL, legacyDefaults: defaults).entries.map(\.text), ["legacy"])
    }

    func testClipboardKeepsNewestImagesWithinByteBudget() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardImages.\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = ClipboardStore(fileURL: fileURL, legacyDefaults: UserDefaults(suiteName: UUID().uuidString)!,
                                   maximumImageBytes: 25)
        store.record(.image(Data(repeating: 1, count: 10)), sourceBundleIdentifier: "a")
        store.record("between")
        store.record(.image(Data(repeating: 2, count: 10)), sourceBundleIdentifier: "a")
        store.record(.image(Data(repeating: 3, count: 10)), sourceBundleIdentifier: "a")
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.last?.text, "between")
    }

    func testClipboardMonitorSkipsConcealedTransientAndPasswordAppContent() {
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        XCTAssertFalse(ClipboardMonitor.shouldRecord(types: [.string, concealed], sourceBundleIdentifier: "com.apple.Safari",
                                                     excludedBundleIdentifiers: []))
        XCTAssertFalse(ClipboardMonitor.shouldRecord(types: [.string, transient], sourceBundleIdentifier: "com.apple.Safari",
                                                     excludedBundleIdentifiers: []))
        XCTAssertFalse(ClipboardMonitor.shouldRecord(types: [.string], sourceBundleIdentifier: "com.apple.Passwords",
                                                     excludedBundleIdentifiers: []))
        XCTAssertFalse(ClipboardMonitor.shouldRecord(types: [.string], sourceBundleIdentifier: "com.example.secret",
                                                     excludedBundleIdentifiers: ["com.example.secret"]))
        XCTAssertTrue(ClipboardMonitor.shouldRecord(types: [.string], sourceBundleIdentifier: "com.apple.Safari",
                                                    excludedBundleIdentifiers: []))
    }

    func testPasteboardSnapshotRestoresEveryType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LaunchDeckTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([1, 2, 3]), forType: custom)
        pasteboard.writeObjects([item])
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied selection", forType: .string)
        snapshot.restore(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "original")
        XCTAssertEqual(pasteboard.data(forType: custom), Data([1, 2, 3]))
    }

    func testSnippetExpandsOnlyDeclaredLocalPlaceholders() {
        let snippet = Snippet(name: "Status", keyword: "status", content: "{date} {time} {clipboard}")
        let output = snippet.expanded(clipboard: "done", now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(output.contains("done"))
        XCTAssertFalse(output.contains("{clipboard}"))
    }

    func testWindowCommandCatalogHasStableIdentifiers() {
        XCTAssertEqual(Set(DesktopWindowCommand.allCases.map(\.rawValue)).count, DesktopWindowCommand.allCases.count)
    }

    func testClipboardPrivacyPreferencesDefaultOffAndPersistExclusions() {
        let suite = "ClipboardPrivacyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences: AppPreferences? = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences!.clipboardEnabled)
        XCTAssertFalse(preferences!.clipboardDisclosureAcknowledged)
        preferences!.clipboardExcludedBundleIdentifiers = ["com.example.secret"]
        preferences = nil
        XCTAssertEqual(AppPreferences(defaults: defaults).clipboardExcludedBundleIdentifiers, ["com.example.secret"])
    }

    func testWindowTargetsCoverHalvesAndQuartersExactly() {
        let frame = CGRect(x: 100, y: 40, width: 1200, height: 800)
        let current = CGRect(x: 200, y: 100, width: 500, height: 400)
        XCTAssertEqual(DesktopWindowController.targetFrame(for: .leftHalf, visibleFrame: frame, currentFrame: current),
                       CGRect(x: 100, y: 40, width: 600, height: 800))
        XCTAssertEqual(DesktopWindowController.targetFrame(for: .bottomRight, visibleFrame: frame, currentFrame: current),
                       CGRect(x: 700, y: 440, width: 600, height: 400))
    }
}
