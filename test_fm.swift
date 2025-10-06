import FoundationModels
import Foundation

@available(macOS 26.0, *)
func testAPI() async throws {
    // Try to discover what's in FoundationModels
    let model = try await FoundationModels.Model()
}
