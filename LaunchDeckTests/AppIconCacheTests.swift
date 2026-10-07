import AppKit
import XCTest
@testable import LaunchDeck

@MainActor
final class AppIconCacheTests: XCTestCase {
    func testConcurrentRequestsForSameIconShareOneLoad() async {
        let counter = IconLoadCounter()
        let cache = AppIconCache { _, size in
            await counter.increment()
            try? await Task.sleep(for: .milliseconds(25))
            return NSImage(size: NSSize(width: size, height: size))
        }

        let completed = expectation(description: "all callbacks complete")
        completed.expectedFulfillmentCount = 3
        for _ in 0..<3 {
            cache.icon(for: "/Applications/Test.app", size: 48) { _ in completed.fulfill() }
        }
        await fulfillment(of: [completed], timeout: 1)
        let loadCount = await counter.currentValue()
        XCTAssertEqual(loadCount, 1)
    }
}

@MainActor
extension AppIconCacheTests {
    func testInvalidationDuringLoadDeliversReloadedIconToWaitingCallers() async {
        let counter = IconLoadCounter()
        let cache = AppIconCache { _, _ in
            let load = await counter.incrementAndGet()
            try? await Task.sleep(for: .milliseconds(30))
            return NSImage(size: NSSize(width: load, height: load))
        }
        let delivered = expectation(description: "waiting tile receives an icon")
        var receivedWidth: CGFloat = 0
        cache.icon(for: "/Applications/Updated.app", size: 48) { image in
            receivedWidth = image.size.width
            delivered.fulfill()
        }
        cache.invalidate(path: "/Applications/Updated.app")
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(receivedWidth, 2, "the icon loaded before the update must be discarded")

        // The fresh icon is cached; a second request does not load again.
        let cached = expectation(description: "cached")
        cache.icon(for: "/Applications/Updated.app", size: 48) { _ in cached.fulfill() }
        await fulfillment(of: [cached], timeout: 1)
        let loads = await counter.currentValue()
        XCTAssertEqual(loads, 2)
    }

    func testInvalidatingOneAppKeepsOtherIconsCached() async {
        let counter = IconLoadCounter()
        let cache = AppIconCache { _, size in
            await counter.increment()
            return NSImage(size: NSSize(width: size, height: size))
        }
        for path in ["/Applications/A.app", "/Applications/B.app"] {
            let loaded = expectation(description: path)
            cache.icon(for: path, size: 48) { _ in loaded.fulfill() }
            await fulfillment(of: [loaded], timeout: 1)
        }
        cache.invalidate(path: "/Applications/A.app")
        let again = expectation(description: "B from cache")
        cache.icon(for: "/Applications/B.app", size: 48) { _ in again.fulfill() }
        await fulfillment(of: [again], timeout: 1)
        let loads = await counter.currentValue()
        XCTAssertEqual(loads, 2)
    }
}

private actor IconLoadCounter {
    func incrementAndGet() -> Int { value += 1; return value }
    private var value = 0
    func increment() { value += 1 }
    func currentValue() -> Int { value }
}
