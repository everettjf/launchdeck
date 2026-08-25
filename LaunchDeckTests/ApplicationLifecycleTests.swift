import AppKit
import XCTest
@testable import LaunchDeck

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testClosingLastWindowKeepsLaunchDeckRunning() {
        let delegate = LaunchDeckAppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
