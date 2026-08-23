import XCTest
@testable import LaunchDeck

final class RecipeTriggerTests: XCTestCase {
    func testAcceptsOnlyLaunchDeckRecipeURLs() {
        let id = UUID()
        XCTAssertEqual(RecipeTrigger.recipeID(from: URL(string: "launchdeck://recipe/\(id)")!), id)
        XCTAssertNil(RecipeTrigger.recipeID(from: URL(string: "https://recipe/\(id)")!))
    }
}
