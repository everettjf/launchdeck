import Foundation
import Testing
@testable import LaunchDeckCore

struct AppSortingTests {
    private func makeApp(identifier: String, name: String) -> DiscoveredApp {
        DiscoveredApp(name: name,
                      bundleIdentifier: identifier,
                      path: "/Applications/\(name).app",
                      category: nil,
                      bundleVersion: nil,
                      developer: nil,
                      isSystemApp: false,
                      keywords: [])
    }

    private func makeRecent(identifier: String, launchCount: Int, lastLaunch: Date) -> RecentLaunch {
        RecentLaunch(identifier: identifier,
                     displayName: identifier,
                     path: "/Applications/\(identifier).app",
                     lastLaunch: lastLaunch,
                     launchCount: launchCount)
    }

    @Test("Alphabetical sorting is case-insensitive")
    func alphabetical() {
        let apps = [makeApp(identifier: "b", name: "bravo"), makeApp(identifier: "a", name: "Alpha"), makeApp(identifier: "c", name: "Charlie")]
        #expect(AppSorting.alphabetical(apps) == ["a", "b", "c"])
    }

    @Test("Most launched sorts by count descending, ties by name")
    func mostLaunched() {
        let now = Date()
        let apps = [makeApp(identifier: "a", name: "Alpha"), makeApp(identifier: "b", name: "Bravo"), makeApp(identifier: "c", name: "Charlie")]
        let recents = [
            makeRecent(identifier: "c", launchCount: 5, lastLaunch: now),
            makeRecent(identifier: "a", launchCount: 5, lastLaunch: now),
        ]
        // a and c tie at 5 launches → name order; b (0 launches) last
        #expect(AppSorting.mostLaunched(apps, recents: recents) == ["a", "c", "b"])
    }

    @Test("Recently launched sorts by date descending, never-launched apps last by name")
    func recentlyLaunched() {
        let now = Date()
        let apps = [makeApp(identifier: "z", name: "Zulu"), makeApp(identifier: "a", name: "Alpha"), makeApp(identifier: "b", name: "Bravo")]
        let recents = [
            makeRecent(identifier: "b", launchCount: 1, lastLaunch: now.addingTimeInterval(-100)),
            makeRecent(identifier: "z", launchCount: 1, lastLaunch: now),
        ]
        #expect(AppSorting.recentlyLaunched(apps, recents: recents) == ["z", "b", "a"])
    }

    @Test("Recording a new launch inserts at the front with count 1")
    func recordNewLaunch() {
        let app = makeApp(identifier: "a", name: "Alpha")
        let recents = RecentLaunchList.recordingLaunch(of: app, in: [], maxCount: 12)
        #expect(recents.count == 1)
        #expect(recents[0].identifier == "a")
        #expect(recents[0].launchCount == 1)
        #expect(recents[0].displayName == "Alpha")
    }

    @Test("Recording an existing launch bumps the count and moves it to the front")
    func recordExistingLaunch() {
        let now = Date()
        let existing = [
            makeRecent(identifier: "a", launchCount: 3, lastLaunch: now.addingTimeInterval(-50)),
            makeRecent(identifier: "b", launchCount: 1, lastLaunch: now.addingTimeInterval(-10)),
        ]
        let app = makeApp(identifier: "b", name: "Bravo")
        let updated = RecentLaunchList.recordingLaunch(of: app, in: existing, maxCount: 12, at: now)
        #expect(updated.map(\.identifier) == ["b", "a"])
        #expect(updated[0].launchCount == 2)
        #expect(updated[0].lastLaunch == now)
    }

    @Test("Recents list is truncated at maxCount")
    func truncatesAtMaxCount() {
        let now = Date()
        let existing = (0..<3).map { makeRecent(identifier: "app\($0)", launchCount: 1, lastLaunch: now) }
        let app = makeApp(identifier: "new", name: "New")
        let updated = RecentLaunchList.recordingLaunch(of: app, in: existing, maxCount: 3)
        #expect(updated.count == 3)
        #expect(updated.map(\.identifier) == ["new", "app0", "app1"])
    }
}
