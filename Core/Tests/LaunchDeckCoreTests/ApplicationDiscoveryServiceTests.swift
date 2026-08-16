import Foundation
import Testing
@testable import LaunchDeckCore

struct ApplicationDiscoveryServiceTests {
    @Test("Nested file events resolve to their application bundle")
    func eventPathNormalization() {
        #expect(ApplicationDiscoveryService.applicationBundlePath(from: "/Applications/Demo.app/Contents/Info.plist") == "/Applications/Demo.app")
        #expect(ApplicationDiscoveryService.applicationBundlePath(from: "/tmp/readme.txt") == nil)
    }

    @Test("Incremental refresh updates only changed bundles")
    func incrementalRefresh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = try makeApplication(named: "First", identifier: "test.first", in: root)
        _ = try makeApplication(named: "Second", identifier: "test.second", in: root)
        let service = ApplicationDiscoveryService(searchPaths: [root])

        #expect(service.discoverApplications(showSystemApps: true).count == 2)
        try FileManager.default.removeItem(at: first)
        let refreshed = service.refreshApplications(changedPaths: [first.path], showSystemApps: true)
        #expect(refreshed.map(\.bundleIdentifier) == ["test.second"])
    }

    private func makeApplication(named name: String, identifier: String, in root: URL) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
