import Foundation
import StartMyAppIndex

let arguments = CommandLine.arguments
let appCount = arguments.firstIndex(of: "--apps").flatMap { index in
    arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
} ?? 1_000

let root = FileManager.default.temporaryDirectory.appendingPathComponent("StartMyAppBenchmark-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

for index in 0..<appCount {
    let contents = root.appendingPathComponent("App\(index).app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "benchmark.app\(index)",
        "CFBundleName": "Benchmark App \(index)",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}

let service = ApplicationDiscoveryService(searchPaths: [root])
let clock = ContinuousClock()
let cold = clock.measure { _ = service.discoverApplications(showSystemApps: true) }
let changedPath = root.appendingPathComponent("App\(appCount / 2).app").path
let incremental = clock.measure {
    _ = service.refreshApplications(changedPaths: [changedPath], showSystemApps: true)
}

print("apps=\(appCount)")
print("cold_index=\(cold)")
print("incremental_refresh=\(incremental)")
