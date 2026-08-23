import Foundation
import LaunchDeckCore
import Testing
@testable import LaunchDeck

struct LocalIndexStoreTests {
    private func temporaryFile(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchDeckStoreTests", isDirectory: true)
            .appendingPathComponent(name)
    }

    @Test func cacheRoundTripsOnlyForMatchingCanonicalRoots() throws {
        let file = temporaryFile()
        let store = LocalIndexStore(fileURL: file)
        defer { try? store.clear() }
        let item = SearchItem(id: "file:a", kind: .file, title: "a", target: .file(path: "/tmp/a"))
        let snapshot = LocalIndexSnapshot(rootPaths: ["/tmp/b/../a", "/tmp/a"], items: [item])
        try store.save(snapshot)

        #expect(store.load(expectedRootPaths: ["/tmp/a"]) == snapshot)
        #expect(store.load(expectedRootPaths: ["/tmp/other"]) == nil)
    }

    @Test func corruptCacheIsRejected() throws {
        let file = temporaryFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(LocalIndexStore(fileURL: file).load(expectedRootPaths: []) == nil)
    }

    @Test func recentDocumentsDeduplicateSortLimitAndDropMissingItems() throws {
        let storeFile = temporaryFile("recents-\(UUID().uuidString)")
        let contentRoot = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckRecentStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: contentRoot, withIntermediateDirectories: true)
        let first = contentRoot.appendingPathComponent("first.md")
        let second = contentRoot.appendingPathComponent("second.md")
        let third = contentRoot.appendingPathComponent("third.md")
        for url in [first, second, third] { FileManager.default.createFile(atPath: url.path, contents: Data()) }
        let store = RecentDocumentStore(maximumCount: 2, fileURL: storeFile)
        defer { try? store.clear(); try? FileManager.default.removeItem(at: contentRoot) }

        try store.record(path: first.path, openedAt: Date(timeIntervalSince1970: 1))
        try store.record(path: second.path, openedAt: Date(timeIntervalSince1970: 2))
        try store.record(path: first.path, openedAt: Date(timeIntervalSince1970: 3))
        try store.record(path: third.path, openedAt: Date(timeIntervalSince1970: 4))
        #expect(store.load(existingOnly: false).map(\.path) == [third.path, first.path])

        try FileManager.default.removeItem(at: third)
        #expect(store.load().map(\.path) == [first.path])
    }
}
