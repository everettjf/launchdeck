import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
final class LocalContentIndexerTests: XCTestCase {
    func testFindsProjectsAndDocumentsWhileSkippingDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckIndexer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Demo.xcodeproj"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Repo/.git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("brief.pdf").path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("node_modules/secret.md").path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: root) }

        let items = LocalContentIndexer().index(configuration: .init(roots: [root]))
        XCTAssertTrue(items.contains { $0.kind == .project && $0.title == "Demo" })
        XCTAssertTrue(items.contains { $0.kind == .project && $0.title == "Repo" })
        XCTAssertTrue(items.contains { $0.kind == .file && $0.title == "brief" })
        XCTAssertFalse(items.contains { $0.title == "secret" })
        XCTAssertTrue(items.contains { $0.kind == .folder && $0.title.hasPrefix("LaunchDeckIndexer-") })
    }

    func testAddsExistingRecentFilesAndFoldersOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckRecent-\(UUID().uuidString)")
        let file = root.appendingPathComponent("recent.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = root.appendingPathComponent("missing.pdf")
        let items = LocalContentIndexer().index(configuration: .init(roots: []), recentURLs: [file, root, missing])
        XCTAssertTrue(items.contains { $0.kind == .file && $0.title == "recent" })
        XCTAssertTrue(items.contains { $0.kind == .folder && $0.title.hasPrefix("LaunchDeckRecent-") })
        XCTAssertFalse(items.contains { $0.title == "missing" })
    }

    func testCancellationStopsScanningWithoutPublishingPartialResults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckCancelled-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<100 {
            XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("file-\(index).md").path,
                                                         contents: Data()))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let items = LocalContentIndexer().index(configuration: .init(roots: [root]),
                                                isCancelled: { true })
        XCTAssertTrue(items.isEmpty)
    }

    func testSinglePathClassificationMatchesFullScan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckSingle-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Docs/Deep"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        for path in ["Docs/brief.pdf", "Docs/Deep/notes.md", "node_modules/skip.md", "App.xcodeproj/inner.md", "archive.zip", "brief.pdf"] {
            XCTAssertTrue(fm.createFile(atPath: root.appendingPathComponent(path).path, contents: Data()))
        }
        defer { try? fm.removeItem(at: root) }

        let indexer = LocalContentIndexer()
        let scanned = Set(indexer.index(configuration: .init(roots: [root])).map(\.id))
        let candidates = ["Docs", "Docs/Deep", "Docs/brief.pdf", "Docs/Deep/notes.md", "node_modules/skip.md",
                          "App.xcodeproj", "App.xcodeproj/inner.md", "archive.zip", "brief.pdf"]
        let single = Set(candidates.compactMap { indexer.item(for: root.appendingPathComponent($0), roots: [root])?.id })
        XCTAssertEqual(single, scanned.subtracting(["folder:\(root.standardizedFileURL.path)"]))
        XCTAssertNil(indexer.item(for: URL(fileURLWithPath: "/tmp/outside.pdf"), roots: [root]))
    }

    func testUndoRecordsDescribeIndexChanges() {
        let record = FileUndoRecord(title: "Move", moves: [.init(source: URL(fileURLWithPath: "/new/a.pdf"),
                                                                 destination: URL(fileURLWithPath: "/old/a.pdf"))],
                                    createdURLs: [URL(fileURLWithPath: "/new/b.zip")])
        XCTAssertEqual(record.change.removedPaths, ["/old/a.pdf"])
        XCTAssertEqual(record.change.addedURLs.map(\.path), ["/new/a.pdf", "/new/b.zip"])
        XCTAssertEqual(record.undoChange.removedPaths, ["/new/a.pdf", "/new/b.zip"])
        XCTAssertEqual(record.undoChange.addedURLs.map(\.path), ["/old/a.pdf"])
    }

    func testFoldersNamedLibraryOutsideTheUserLibraryAreIndexed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryName-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Project/Library"), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("Project/Library/guide.md").path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: root) }
        let items = LocalContentIndexer().index(configuration: .init(roots: [root]))
        XCTAssertTrue(items.contains { $0.title == "guide" })
        let userLibrary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/x.md")
        XCTAssertNil(LocalContentIndexer().item(for: userLibrary, roots: [FileManager.default.homeDirectoryForCurrentUser]))
    }
}
