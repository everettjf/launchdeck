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

    func testQuicklinkEscapesQueryDelimitersInTheSearchTerm() throws {
        let quicklink = Quicklink(name: "Google", keyword: "g", urlTemplate: "https://www.google.com/search?q={query}")
        let url = try XCTUnwrap(quicklink.url(for: "a&b=c+d #e?"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?.value, "a&b=c+d #e?")
        XCTAssertNil(url.fragment)
    }

    func testDeeplyNestedParenthesesAreRejectedWithoutRecursingForever() {
        let nested = String(repeating: "(", count: 5_000) + "1+1" + String(repeating: ")", count: 5_000)
        XCTAssertTrue(UtilitySearchProvider.results(for: nested).filter { $0.kind == .calculation }.isEmpty)
        XCTAssertEqual(UtilitySearchProvider.results(for: "((1+2))*3").first?.title, "9")
    }

    func testProviderErrorDetailUsesTheMessageField() {
        let body = Data(#"{"error":{"type":"invalid_request_error","message":"model not found"}}"#.utf8)
        XCTAssertEqual(AIProviderClient.errorDetail(from: body), "model not found")
        XCTAssertEqual(AIProviderClient.errorDetail(from: Data("Bad Gateway".utf8)), "Bad Gateway")
        XCTAssertNil(AIProviderClient.errorDetail(from: Data()))
    }
}
