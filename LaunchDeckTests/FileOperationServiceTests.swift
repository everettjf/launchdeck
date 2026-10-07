import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
final class FileOperationServiceTests: XCTestCase {
    func testRenameDuplicateMoveCompressAndRecentDestination() async throws {
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
        let archive = try await service.compress(renamed)
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

    func testClearRecentDestinationsForgetsEveryFolder() throws {
        let suite = "FileOperationDestinations.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        let service = FileOperationService(defaults: defaults)
        _ = try service.move([file], to: destination)
        XCTAssertFalse(service.recentDestinationPaths.isEmpty)
        service.clearRecentDestinations()
        XCTAssertTrue(service.recentDestinationPaths.isEmpty)
    }

    func testProcessRunnerDrainsLargeStandardErrorWithoutDeadlock() async throws {
        // More than a pipe buffer (64 KB) of stderr would hang a wait-then-read implementation.
        let result = try await ProcessRunner.run(executable: "/bin/sh",
                                                 arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.standardError.count, 300_000)
    }

    func testProcessRunnerTerminatesOnCancellation() async throws {
        let task = Task { try await ProcessRunner.run(executable: "/bin/sleep", arguments: ["30"]) }
        try await Task.sleep(for: .milliseconds(100))
        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testCompressingSameBaseNamesDoesNotCollide() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("a.pdf"), docx = root.appendingPathComponent("a.docx")
        try Data("1".utf8).write(to: pdf)
        try Data("2".utf8).write(to: docx)
        let service = FileOperationService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let undo = try await service.compressWithUndo([pdf, docx])
        XCTAssertEqual(undo.createdURLs.map(\.lastPathComponent), ["a.pdf.zip", "a.docx.zip"])
        let again = try await service.compress(pdf)
        XCTAssertEqual(again.lastPathComponent, "a.pdf 2.zip")
    }
}
