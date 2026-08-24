import AppKit
import Testing
@testable import LaunchDeck

struct StatusItemIconTests {
    @Test func iconUsesAStandardTransparentTemplateImage() {
        let icon = StatusItemIcon.make(accessibilityDescription: "LaunchDeck")

        #expect(icon.size == NSSize(width: 18, height: 18))
        #expect(icon.isTemplate)
        #expect(icon.accessibilityDescription == "LaunchDeck")
    }

    @Test func iconLeavesItsCornersTransparent() throws {
        let icon = StatusItemIcon.make(accessibilityDescription: "LaunchDeck")
        let representation = try #require(NSBitmapImageRep(data: icon.tiffRepresentation!))

        #expect(representation.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(representation.colorAt(x: representation.pixelsWide - 1,
                                       y: representation.pixelsHigh - 1)?.alphaComponent == 0)
    }
}
