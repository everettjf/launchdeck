import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
final class LocalContentCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Coordinator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Docs"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeCoordinator() -> LocalContentCoordinator {
        LocalContentCoordinator(store: LocalIndexStore(fileURL: root.appendingPathComponent("index.json")),
                                recentDocumentStore: RecentDocumentStore(fileURL: root.appendingPathComponent("recent.json")),
                                rootPaths: { [root] in [root!.path] })
    }

    func testRenameUpdatesItemsInPlaceAndNotifies() throws {
        let coordinator = makeCoordinator()
        var notifications = 0
        coordinator.itemsChanged = { notifications += 1 }
        let original = root.appendingPathComponent("Docs/brief.pdf")
        let renamed = root.appendingPathComponent("Docs/final.pdf")
        try Data().write(to: original)
        coordinator.apply(LocalContentChange(addedURLs: [original]))
        XCTAssertEqual(coordinator.items.map(\.title), ["brief"])

        try FileManager.default.moveItem(at: original, to: renamed)
        coordinator.apply(LocalContentChange(removedPaths: [original.path], addedURLs: [renamed]))
        XCTAssertEqual(coordinator.items.map(\.title), ["final"])
        XCTAssertEqual(notifications, 2)
        coordinator.apply(.none)
        XCTAssertEqual(notifications, 2)
    }

    func testRecentDocumentOutsideRootsIsAddedOnce() throws {
        let coordinator = makeCoordinator()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).md")
        try Data().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        coordinator.recordRecentDocument(outside.path)
        coordinator.recordRecentDocument(outside.path)
        XCTAssertEqual(coordinator.items.filter { $0.fileSystemPath == outside.path }.count, 1)
        XCTAssertTrue(coordinator.items.first?.keywords.contains("recent") == true)
    }
}

@MainActor
final class UnifiedIndexCoordinatorTests: XCTestCase {
    func testOnlyTheNewestRebuildIsPublished() async throws {
        let coordinator = UnifiedIndexCoordinator()
        let app = DiscoveredApp(name: "Safari", bundleIdentifier: "com.apple.Safari", path: "/Applications/Safari.app",
                                category: nil, bundleVersion: nil, developer: nil, isSystemApp: true, keywords: [])
        coordinator.rebuild(apps: [], indexedItems: [], approvedShortcuts: [], recipes: [])
        coordinator.rebuild(apps: [app], indexedItems: [], approvedShortcuts: [], recipes: [])
        for _ in 0..<100 where coordinator.revision == 0 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.revision, 1)
        XCTAssertNotNil(coordinator.item(identifier: "application:com.apple.Safari"))
        XCTAssertEqual(coordinator.index.search("safari").first?.item.title, "Safari")
    }
}
