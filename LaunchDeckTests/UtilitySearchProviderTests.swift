import XCTest
@testable import LaunchDeck

final class UtilitySearchProviderTests: XCTestCase {
    func testArithmeticPrecedenceAndInvalidInput() {
        XCTAssertEqual(UtilitySearchProvider.results(for: "2 + 3 * 4").first?.title, "14")
        XCTAssertTrue(UtilitySearchProvider.results(for: "2 / 0").isEmpty)
    }

    func testQuicklinkProducesValidatedHTTPSTarget() {
        let result = UtilitySearchProvider.results(for: "g launchdeck").first { $0.kind == .quicklink }
        guard case .url(let url) = result?.target else { return XCTFail("Expected URL target") }
        XCTAssertEqual(url.scheme, "https")
    }

    func testUnitAndTemperatureConversions() {
        XCTAssertEqual(UtilitySearchProvider.results(for: "1 km to m").first?.title, "1,000 m")
        XCTAssertEqual(UtilitySearchProvider.results(for: "32 f to c").first?.title, "0 c")
    }

    func testCustomQuicklinkAndUnsafeTemplateValidation() {
        let link = Quicklink(name: "Docs", keyword: "docs", urlTemplate: "https://example.com/?q={query}")
        XCTAssertNotNil(UtilitySearchProvider.results(for: "docs swift", quicklinks: [link]).first)
        XCTAssertNotNil(QuicklinkValidation.error(for: .init(name: "Bad", keyword: "bad", urlTemplate: "file:///tmp/{query}")))
    }
}
