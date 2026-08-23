import XCTest
@testable import LaunchDeck

@MainActor
final class FileOperationServiceTests: XCTestCase {
    func testRenameDuplicateMoveCompressAndRecentDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileOperationTests-\(UUID())")
        let sourceDirectory = root.appendingPathComponent("source")
        let destinationDirectory = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FileOperationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = FileOperationService(defaults: defaults)
        let original = sourceDirectory.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: original)

        let renamed = try service.rename(original, to: "renamed.txt")
        let duplicate = try service.duplicate(renamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicate.path))
        let archive = try service.compress(renamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        let moved = try service.move([duplicate], to: destinationDirectory)
        XCTAssertEqual(moved.first?.deletingLastPathComponent().standardizedFileURL.path,
                       destinationDirectory.standardizedFileURL.path)
        XCTAssertEqual(service.recentDestinationPaths.first, destinationDirectory.path)
    }

    func testRejectsInvalidRenameAndOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileOperationTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let existing = root.appendingPathComponent("existing")
        try Data().write(to: source)
        try Data().write(to: existing)
        let service = FileOperationService()
        XCTAssertThrowsError(try service.rename(source, to: "bad/name"))
        XCTAssertThrowsError(try service.rename(source, to: "existing"))
    }
}
