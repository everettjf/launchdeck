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

private actor IconLoadCounter {
    private var value = 0
    func increment() { value += 1 }
    func currentValue() -> Int { value }
}
