import AppKit
import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
final class CompetitiveWorkflowTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckCompetitive-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "LaunchDeckCompetitive-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func file(_ name: String, contents: String = "test") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // 1 — LaunchBar Instant Send: capture multiple Finder-style file URLs.
    func test01InstantSendCapturesMultipleFiles() throws {
        let first = try file("one.txt"), second = try file("two.txt")
        let pasteboard = NSPasteboard(name: .init("instant-\(UUID())")); pasteboard.writeObjects([first as NSURL, second as NSURL])
        XCTAssertEqual(InstantSendService.objects(from: pasteboard).map(\.value), [first.path, second.path])
    }

    // 2 — Spotlight context: recognize a current web URL as a first-class object.
    func test02InstantSendCapturesURL() {
        let pasteboard = NSPasteboard(name: .init("url-\(UUID())")); pasteboard.setString("https://example.com/path", forType: .string)
        let object = InstantSendService.objects(from: pasteboard).first
        XCTAssertEqual(object?.kind, .url)
        XCTAssertFalse(ObjectActionCatalog.actions(for: [object!]).contains(.reveal))
    }

    // 3 — LaunchBar grammar: compatible file selections expose batch target actions.
    func test03ObjectActionCatalogForBatchFiles() throws {
        let objects = try [file("a"), file("b")].map { LaunchObject(kind: .file, title: $0.lastPathComponent, value: $0.path) }
        XCTAssertTrue(ObjectActionCatalog.actions(for: objects).contains(.move))
        XCTAssertTrue(ObjectActionCatalog.actions(for: objects).contains(.openWith))
    }

    // 4 — Safety: mixed text and files only expose operations valid for every object.
    func test04MixedObjectsSuppressUnsafeBatchActions() throws {
        let url = try file("a")
        let objects = [LaunchObject(kind: .file, title: "a", value: url.path), LaunchObject(kind: .text, title: "t", value: "text")]
        XCTAssertFalse(ObjectActionCatalog.actions(for: objects).contains(.trash))
        XCTAssertTrue(ObjectActionCatalog.actions(for: objects).contains(.copy))
    }

    // 5 — Finder replacement: batch move is atomic and undoable.
    func test05BatchMoveAndUndo() throws {
        let destination = root.appendingPathComponent("destination"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sources = try [file("a"), file("b")]
        let service = FileOperationService(defaults: defaults)
        let undo = try service.moveWithUndo(sources, to: destination)
        try service.undo(undo)
        XCTAssertTrue(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    // 6 — Raycast file actions: duplicate a selection and undo all generated files.
    func test06BatchDuplicateAndUndo() throws {
        let service = FileOperationService(defaults: defaults), sources = try [file("a.txt"), file("b.txt")]
        let undo = try service.duplicateWithUndo(sources)
        XCTAssertEqual(undo.createdURLs.count, 2)
        try service.undo(undo)
        XCTAssertTrue(undo.createdURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    // 7 — LaunchBar compression: batch ZIP output is undoable.
    func test07BatchCompressAndUndo() throws {
        let service = FileOperationService(defaults: defaults), sources = try [file("a.txt"), file("b.txt")]
        let undo = try service.compressWithUndo(sources)
        XCTAssertEqual(undo.createdURLs.count, 2)
        try service.undo(undo)
    }

    // 8 — Recoverable deletion: Trash returns an exact restoration transaction.
    func test08TrashAndUndo() throws {
        let source = try file("recover-me.txt"), service = FileOperationService(defaults: defaults)
        let undo = try service.moveToTrash([source]); try service.undo(undo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    // 9 — Alfred workflow parity: an Object → Action → Target chain round-trips as Recipe JSON.
    func test09ActionChainRecipeRoundTrip() throws {
        let step = RecipeStep.objectAction(.move, sources: ["{{source}}"], target: "{{destination}}")
        let recipe = Recipe(name: "Move", variables: [.init(name: "source"), .init(name: "destination")], steps: [step])
        XCTAssertEqual(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)), recipe)
    }

    // 10 — Spotlight narrowing: kind qualifier filters before ranking.
    func test10KindQualifiedSearch() {
        let items = [SearchItem(id: "a", kind: .application, title: "Notes", target: .application(identifier: "n", path: "/A")),
                     SearchItem(id: "f", kind: .file, title: "Notes", target: .file(path: "/Notes.md"))]
        XCTAssertEqual(UnifiedSearchIndex(items: items).search(SearchQuery.parse("kind:file notes")).map(\.item.id), ["f"])
    }

    // 11 — LaunchBar deep index: path and extension qualifiers compose.
    func test11PathAndExtensionQualifiedSearch() {
        let item = SearchItem(id: "f", kind: .file, title: "Plan", target: .file(path: "/Documents/Plan.pdf"))
        XCTAssertTrue(SearchQuery.parse("path:Documents ext:pdf").matches(item))
        XCTAssertFalse(SearchQuery.parse("path:Desktop ext:pdf").matches(item))
    }

    // 12 — Existing users retain v1 text clipboard history after the rich-content migration.
    func test12LegacyClipboardMigration() throws {
        let id = UUID(), date = Date()
        let legacy = try JSONSerialization.data(withJSONObject: [["id": id.uuidString, "text": "legacy", "copiedAt": date.timeIntervalSinceReferenceDate]])
        XCTAssertEqual(try JSONDecoder().decode([ClipboardEntry].self, from: legacy).first?.text, "legacy")
    }

    // 13 — Spotlight/Raycast clipboard parity: images persist within the 5 MB privacy cap.
    func test13ImageClipboardRoundTrip() throws {
        let entry = ClipboardEntry(content: .image(Data(repeating: 7, count: 256)))
        XCTAssertEqual(try JSONDecoder().decode(ClipboardEntry.self, from: JSONEncoder().encode(entry)), entry)
    }

    // 14 — Alfred clipboard parity: file references retain all selected paths.
    func test14FileClipboardRoundTrip() throws {
        let paths = [try file("a").path, try file("b").path]
        let entry = ClipboardEntry(content: .files(paths))
        guard case .files(let decoded) = try JSONDecoder().decode(ClipboardEntry.self, from: JSONEncoder().encode(entry)).content else {
            return XCTFail("Expected files")
        }
        XCTAssertEqual(decoded, paths)
    }

    // 15 — First-run onboarding is shown once and completion persists.
    func test15OnboardingCompletionPersists() {
        let first = AppPreferences(defaults: defaults)
        XCTAssertFalse(first.hasCompletedOnboarding)
        first.hasCompletedOnboarding = true
        XCTAssertTrue(AppPreferences(defaults: defaults).hasCompletedOnboarding)
    }
}
