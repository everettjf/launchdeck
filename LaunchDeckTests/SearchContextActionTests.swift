import LaunchDeckCore
import XCTest
@testable import LaunchDeck

final class SearchContextActionTests: XCTestCase {
    func testFileActionsAreContextualAndStable() {
        let file = SearchItem(id: "file:/tmp/a", kind: .file, title: "A", target: .file(path: "/tmp/a"))
        XCTAssertEqual(SearchContextActionCatalog.actions(for: file), [.open, .quickLook, .reveal, .copyPath])
    }

    func testActionsThatNeedTargetsDoNotOfferContextlessOperations() {
        let action = SearchItem(id: "action:open.file", kind: .action, title: "Open File",
                                target: .registeredAction(identifier: "open.file"))
        XCTAssertTrue(SearchContextActionCatalog.actions(for: action).isEmpty)
    }
}
