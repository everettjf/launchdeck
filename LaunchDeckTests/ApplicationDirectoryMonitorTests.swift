import XCTest
@testable import LaunchDeck

final class ApplicationDirectoryMonitorTests: XCTestCase {
    func testStartStopAndDeallocationAreSafeFromAnyThread() {
        for _ in 0..<20 {
            var monitor: ApplicationDirectoryMonitor? = ApplicationDirectoryMonitor { _ in }
            monitor?.startMonitoring()
            monitor?.startMonitoring()
            let stopper = monitor
            DispatchQueue.concurrentPerform(iterations: 4) { _ in stopper?.stopMonitoring() }
            monitor?.startMonitoring()
            monitor = nil
        }
    }
}
