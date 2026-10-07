import AppKit
import XCTest
import LaunchDeckCore
@testable import LaunchDeck

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testClosingLastWindowKeepsLaunchDeckRunning() {
        let delegate = LaunchDeckAppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
