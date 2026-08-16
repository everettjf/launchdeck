import Foundation
import Testing
@testable import LaunchDeckCore

struct LayoutSynchronizerTests {
    private func makeApp(identifier: String, name: String? = nil) -> DiscoveredApp {
        DiscoveredApp(name: name ?? identifier,
                      bundleIdentifier: identifier,
                      path: "/Applications/\(name ?? identifier).app",
                      category: nil,
                      bundleVersion: nil,
                      developer: nil,
                      isSystemApp: false,
                      keywords: [])
    }

    @Test("Uninstalled apps are dropped, existing order is preserved")
    func dropsUnknownApps() {
        let layout: [AppCollectionItem] = [.app("com.test.a"), .app("com.test.gone"), .app("com.test.b")]
        let synced = LayoutSynchronizer.sync(layout: layout, with: [makeApp(identifier: "com.test.a"), makeApp(identifier: "com.test.b")])
        #expect(synced == [.app("com.test.a"), .app("com.test.b")])
    }

    @Test("Newly discovered apps are appended sorted by name, case-insensitively")
    func appendsMissingAppsSorted() {
        let layout: [AppCollectionItem] = [.app("com.test.a")]
        let apps = [
            makeApp(identifier: "com.test.a", name: "Alpha"),
            makeApp(identifier: "com.test.z", name: "zulu"),
            makeApp(identifier: "com.test.b", name: "Bravo"),
        ]
        let synced = LayoutSynchronizer.sync(layout: layout, with: apps)
        #expect(synced == [.app("com.test.a"), .app("com.test.b"), .app("com.test.z")])
    }

    @Test("Folder with two or more surviving apps is kept and pruned")
    func keepsFolderWithTwoApps() {
        let folder = AppCollectionItem.folder(id: "folder-1", name: "Tools",
                                              appIdentifiers: ["com.test.a", "com.test.gone", "com.test.b"])
        let synced = LayoutSynchronizer.sync(layout: [folder],
                                             with: [makeApp(identifier: "com.test.a"), makeApp(identifier: "com.test.b")])
        #expect(synced.count == 1)
        #expect(synced[0].id == "folder-1")
        #expect(synced[0].folder?.appIdentifiers == ["com.test.a", "com.test.b"])
    }

    @Test("Folder reduced to one app is promoted to a plain app item")
    func promotesSingletonFolder() {
        let folder = AppCollectionItem.folder(id: "folder-1", name: "Tools",
                                              appIdentifiers: ["com.test.a", "com.test.gone"])
        let synced = LayoutSynchronizer.sync(layout: [folder], with: [makeApp(identifier: "com.test.a")])
        #expect(synced == [.app("com.test.a")])
    }

    @Test("Folder with no surviving apps is removed")
    func removesEmptyFolder() {
        let folder = AppCollectionItem.folder(id: "folder-1", name: "Tools",
                                              appIdentifiers: ["com.test.gone"])
        let synced = LayoutSynchronizer.sync(layout: [.app("com.test.a"), folder],
                                             with: [makeApp(identifier: "com.test.a")])
        #expect(synced == [.app("com.test.a")])
    }

    @Test("Folder dissolution rule: 2+ keep, 1 promote, 0 remove")
    func folderDissolutionRule() {
        let base = AppCollectionItem.folder(id: "f", name: "F", appIdentifiers: ["a", "b", "c"])
        var folder = base.folder!

        folder.appIdentifiers = ["a", "b"]
        let kept = FolderDissolution.item(for: folder, reusing: base)
        #expect(kept?.kind == .folder)
        #expect(kept?.id == "f")

        folder.appIdentifiers = ["a"]
        #expect(FolderDissolution.item(for: folder, reusing: base) == .app("a"))

        folder.appIdentifiers = []
        #expect(FolderDissolution.item(for: folder, reusing: base) == nil)
    }

    @Test("Suggested folder name uses the most common category")
    func folderNaming() {
        let apps = [
            DiscoveredApp(name: "A", bundleIdentifier: "a", path: "/a", category: "Productivity",
                          bundleVersion: nil, developer: nil, isSystemApp: false, keywords: []),
            DiscoveredApp(name: "B", bundleIdentifier: "b", path: "/b", category: "Productivity",
                          bundleVersion: nil, developer: nil, isSystemApp: false, keywords: []),
            DiscoveredApp(name: "C", bundleIdentifier: "c", path: "/c", category: "Games",
                          bundleVersion: nil, developer: nil, isSystemApp: false, keywords: []),
        ]
        let lookup = Dictionary(uniqueKeysWithValues: apps.map { ($0.identifier, $0) })
        #expect(FolderNaming.suggestedName(forAppIdentifiers: ["a", "b", "c"], appsByIdentifier: lookup) == "Productivity")
        #expect(FolderNaming.suggestedName(forAppIdentifiers: ["unknown"], appsByIdentifier: lookup) == nil)
    }
}
