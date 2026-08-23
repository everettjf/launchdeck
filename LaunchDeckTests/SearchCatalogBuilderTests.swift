import XCTest
import LaunchDeckCore
@testable import LaunchDeck

final class SearchCatalogBuilderTests: XCTestCase {
    func testCatalogContainsEveryRequiredSearchKind() {
        let app = DiscoveredApp(name: "Editor", bundleIdentifier: "com.test.editor", path: "/Editor.app",
                                category: "Graphics", bundleVersion: nil, developer: "Test", isSystemApp: false,
                                keywords: ["image"])
        let folder = SearchItem(id: "folder:/tmp", kind: .folder, title: "Work", target: .folder(path: "/tmp"))
        let file = SearchItem(id: "file:/tmp/a.pdf", kind: .file, title: "A", target: .file(path: "/tmp/a.pdf"))
        let project = SearchItem(id: "project:/tmp/p", kind: .project, title: "P", target: .project(path: "/tmp/p"))
        let recipe = Recipe(name: "Start", steps: [.openApplication(identifier: app.identifier, name: app.name)])
        let catalog = SearchCatalogBuilder.build(apps: [app], indexedItems: [folder, file, project],
                                                 approvedShortcuts: ["Export"], recipes: [recipe])
        let kinds = Set(catalog.map(\.kind))
        XCTAssertTrue([SearchItemKind.application, .file, .folder, .project, .action, .setting, .shortcut, .recipe]
            .allSatisfy(kinds.contains))
        XCTAssertTrue(catalog.contains { $0.id == "action:open.file-with" })
    }
}
