import XCTest
@testable import LaunchDeck

@MainActor
final class ExtensionStoreTests: XCTestCase {
    func testInstallsSearchesReloadsAndUninstallsValidatedManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionStoreTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = ExtensionManifest(
            schemaVersion: 1, id: "com.test.docs", name: "Docs", version: "1.0.0", permissions: [.network],
            commands: [.init(id: "search", name: "Search Docs", kind: .quicklink,
                             value: "https://example.com/?q={query}", keyword: "docs")]
        )
        let store = ExtensionStore(directory: directory)
        try store.install(data: JSONEncoder().encode(manifest))
        XCTAssertEqual(store.manifests, [manifest])
        XCTAssertEqual(store.searchItems(matching: "docs swift").first?.kind, .extensionCommand)
        XCTAssertEqual(ExtensionStore(directory: directory).manifests, [manifest])
        try store.uninstall(id: manifest.id)
        XCTAssertTrue(store.manifests.isEmpty)
    }

    func testRejectsUndeclaredNetworkAndUnsupportedSchema() throws {
        let manifest = ExtensionManifest(
            schemaVersion: 2, id: "com.test.bad", name: "Bad", version: "1", permissions: [],
            commands: [.init(id: "url", name: "URL", kind: .openURL, value: "https://example.com", keyword: nil)]
        )
        let errors = ExtensionManifestValidation.errors(in: manifest)
        XCTAssertTrue(errors.contains { $0.contains("schemaVersion") })
        XCTAssertTrue(errors.contains { $0.contains("network permission") })
    }
}
