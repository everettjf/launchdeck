import Foundation
import LaunchDeckCore
import Darwin

let arguments = CommandLine.arguments
let appCount = arguments.firstIndex(of: "--apps").flatMap { index in
    arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
} ?? 1_000

let root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchDeckBenchmark-\(UUID().uuidString)")
func residentMemoryMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
}
let baselineMemoryMB = residentMemoryMB()
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

let apps = service.discoverApplications(showSystemApps: true)
let indexBuild = clock.measure { _ = SearchIndex(apps: apps) }
let searchIndex = SearchIndex(apps: apps)
let queries = ["app", "ba5", "benchmark app 50", "benchmrk app 50"]
var searchNanoseconds: [Int64] = []
var querySamples: [String: [Int64]] = Dictionary(uniqueKeysWithValues: queries.map { ($0, []) })
for iteration in 0..<100 {
    let query = queries[iteration % queries.count]
    let duration = clock.measure { _ = searchIndex.search(query, limit: 20) }
    let components = duration.components
    searchNanoseconds.append(components.seconds * 1_000_000_000 + Int64(components.attoseconds / 1_000_000_000))
    querySamples[query, default: []].append(searchNanoseconds.last!)
}
searchNanoseconds.sort()
@MainActor func percentile(_ value: Double) -> Double {
    let index = min(searchNanoseconds.count - 1, Int(Double(searchNanoseconds.count - 1) * value))
    return Double(searchNanoseconds[index]) / 1_000_000
}
func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
}
func p95Milliseconds(_ samples: [Int64]) -> Double {
    let sorted = samples.sorted()
    return Double(sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]) / 1_000_000
}

let burst = clock.measure {
    for query in ["b", "be", "ben", "benc", "bench", "benchm", "benchma", "benchmark", "benchmark app", "benchmark app 5"] {
        _ = searchIndex.search(query, limit: 20)
    }
}
let semanticOptIn = clock.measure {
    let ranked = searchIndex.search("edit an image", limit: 40)
    let rankedIDs = Set(ranked.map { $0.app.identifier })
    _ = ranked + apps.lazy.filter { !rankedIDs.contains($0.identifier) }.prefix(40 - ranked.count).map { (app: $0, score: 0.0) }
}

let unifiedItems = apps.enumerated().flatMap { offset, app -> [SearchItem] in
    let application = SearchItem(id: "application:\(app.identifier)", kind: .application,
                                 title: app.name, keywords: app.keywords,
                                 target: .application(identifier: app.identifier, path: app.path))
    let document = SearchItem(id: "file:/Documents/Brief\(offset).pdf", kind: .file,
                              title: "Brief \(offset)", keywords: ["pdf", "document"],
                              target: .file(path: "/Documents/Brief\(offset).pdf"))
    return [application, document]
}
let unifiedBuild = clock.measure { _ = UnifiedSearchIndex(items: unifiedItems) }
let unifiedIndex = UnifiedSearchIndex(items: unifiedItems)
let indexedMemoryMB = residentMemoryMB()
var unifiedSamples: [Int64] = []
var qualifiedSamples: [Int64] = []
for iteration in 0..<100 {
    let duration = clock.measure { _ = unifiedIndex.search(iteration.isMultiple(of: 2) ? "benchmark app 50" : "brief 50", limit: 20) }
    unifiedSamples.append(duration.components.seconds * 1_000_000_000
                          + Int64(duration.components.attoseconds / 1_000_000_000))
    let qualified = clock.measure {
        _ = unifiedIndex.search(SearchQuery.parse(iteration.isMultiple(of: 2) ? "kind:file ext:pdf brief 50" : "app:benchmark app 50"), limit: 20)
    }
    qualifiedSamples.append(qualified.components.seconds * 1_000_000_000
                            + Int64(qualified.components.attoseconds / 1_000_000_000))
}

let unifiedBurstQueries = ["b", "br", "bri", "brie", "brief", "brief 5", "brief 50",
                           "benchmark", "benchmark app", "benchmark app 50"]
let unifiedBurst = clock.measure {
    for query in unifiedBurstQueries { _ = unifiedIndex.search(SearchQuery.parse(query), limit: 20) }
}
let qualifiedBurst = clock.measure {
    for query in unifiedBurstQueries {
        _ = unifiedIndex.search(SearchQuery.parse("kind:file ext:pdf \(query)"), limit: 20)
    }
}
let rebuildFive = clock.measure {
    for _ in 0..<5 { _ = UnifiedSearchIndex(items: unifiedItems) }
}
let memoryBeforeDurabilityMB = residentMemoryMB()
let durability = clock.measure {
    for iteration in 0..<100 {
        let query = unifiedBurstQueries[iteration % unifiedBurstQueries.count]
        _ = unifiedIndex.search(SearchQuery.parse(query), limit: 20)
    }
}
let memoryAfterDurabilityMB = residentMemoryMB()

let output: [String: Any] = [
    "apps": appCount,
    "cold_index_ms": milliseconds(cold),
    "incremental_refresh_ms": milliseconds(incremental),
    "search_index_build_ms": milliseconds(indexBuild),
    "search_p50_ms": percentile(0.50),
    "search_p95_ms": percentile(0.95),
    "iterations": searchNanoseconds.count,
    "continuous_10_queries_ms": milliseconds(burst),
    "intent_candidate_retrieval_ms": milliseconds(semanticOptIn),
    "unified_items": unifiedItems.count,
    "unified_index_build_ms": milliseconds(unifiedBuild),
    "unified_search_p95_ms": p95Milliseconds(unifiedSamples),
    "qualified_search_p95_ms": p95Milliseconds(qualifiedSamples),
    "unified_continuous_10_queries_ms": milliseconds(unifiedBurst),
    "qualified_continuous_10_queries_ms": milliseconds(qualifiedBurst),
    "unified_rebuild_5_ms": milliseconds(rebuildFive),
    "durability_100_searches_ms": milliseconds(durability),
    "post_durability_memory_growth_mb": max(0, memoryAfterDurabilityMB - memoryBeforeDurabilityMB),
    "resident_memory_mb": indexedMemoryMB,
    "index_memory_delta_mb": max(0, indexedMemoryMB - baselineMemoryMB),
    "query_p95_ms": Dictionary(uniqueKeysWithValues: querySamples.map { ($0.key, p95Milliseconds($0.value)) }),
]
let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
