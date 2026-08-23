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
        XCTAssertEqual(try JSONDecoder().decode(ExtensionManifest.self, from: store.exportData(id: manifest.id)), manifest)
        XCTAssertEqual(store.searchItems(matching: "docs swift").first?.kind, .extensionCommand)
        XCTAssertEqual(ExtensionStore(directory: directory).manifests, [manifest])
        try store.uninstall(id: manifest.id)
        XCTAssertTrue(store.manifests.isEmpty)
    }

    func testRejectsUndeclaredNetworkInvalidVersionAndUnsupportedSchema() throws {
        let manifest = ExtensionManifest(
            schemaVersion: 3, id: "com.test.bad", name: "Bad", version: "1", permissions: [],
            commands: [.init(id: "url", name: "URL", kind: .openURL, value: "https://example.com", keyword: nil)]
        )
        let errors = ExtensionManifestValidation.errors(in: manifest)
        XCTAssertTrue(errors.contains { $0.contains("schemaVersion") })
        XCTAssertTrue(errors.contains { $0.contains("network permission") })
        XCTAssertTrue(errors.contains { $0.contains("semantic versioning") })
    }

    func testV2UpdateRequiresApprovalForExpandedPermissionsAndWritesIntegrityRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionStoreTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = ExtensionManifest.Command(id: "text", name: "Text", kind: .staticText, value: "hello", keyword: nil)
        let first = ExtensionManifest(schemaVersion: 2, id: "com.test.v2", name: "V2", version: "1.0.0",
                                      permissions: [], commands: [command])
        let updated = ExtensionManifest(schemaVersion: 2, id: first.id, name: first.name, version: "1.1.0",
                                        minimumLaunchDeckVersion: "1.5.0", publisher: "Test",
                                        permissions: [.files], commands: [command])
        let store = ExtensionStore(directory: directory)
        try store.install(data: JSONEncoder().encode(first))
        XCTAssertThrowsError(try store.install(data: JSONEncoder().encode(updated))) { error in
            XCTAssertEqual(error as? ExtensionStoreError, .permissionExpansion([.files]))
        }
        try store.install(data: JSONEncoder().encode(updated), allowPermissionExpansion: true)
        XCTAssertEqual(store.manifests.first?.version, "1.1.0")
        let recordURL = directory.appendingPathComponent(first.id).appendingPathComponent("installation.json")
        let record = try JSONDecoder().decode(ExtensionInstallationRecord.self, from: Data(contentsOf: recordURL))
        XCTAssertEqual(record.version, "1.1.0")
        XCTAssertEqual(record.sha256.count, 64)
    }
}
