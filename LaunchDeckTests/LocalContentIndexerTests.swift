import XCTest
import LaunchDeckCore
@testable import LaunchDeck

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
}
