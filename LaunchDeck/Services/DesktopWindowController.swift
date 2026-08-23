import AppKit
import ApplicationServices

enum DesktopWindowCommand: String, CaseIterable, Sendable {
    case leftHalf = "window.left"
    case rightHalf = "window.right"
    case maximize = "window.maximize"
    case center = "window.center"

    var title: String {
        switch self {
        case .leftHalf: "Move Window to Left Half"
        case .rightHalf: "Move Window to Right Half"
        case .maximize: "Maximize Window"
        case .center: "Center Window"
        }
    }
}

@MainActor
enum DesktopWindowController {
    static func perform(_ command: DesktopWindowCommand) -> String? {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return "Enable Accessibility access for LaunchDeck, then retry the window action."
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let screen = NSScreen.main else { return "No frontmost application window is available." }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "The frontmost app did not expose a movable window." }
        let frame = screen.visibleFrame
        let target: CGRect
        switch command {
        case .leftHalf: target = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .rightHalf: target = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .maximize: target = frame
        case .center:
            target = CGRect(x: frame.midX - frame.width * 0.35, y: frame.midY - frame.height * 0.35,
                            width: frame.width * 0.7, height: frame.height * 0.7)
        }
        let element = unsafeBitCast(window, to: AXUIElement.self)
        var position = target.origin
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return "Could not encode the requested window frame."
        }
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        return positionResult == .success && sizeResult == .success ? nil : "The frontmost app refused the requested window frame."
    }
}
