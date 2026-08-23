import AppKit
import ApplicationServices

enum AccessibilityPermissionStatus: Equatable, Sendable { case granted, denied }

enum DesktopWindowCommand: String, CaseIterable, Sendable {
    case leftHalf = "window.left", rightHalf = "window.right"
    case topHalf = "window.top", bottomHalf = "window.bottom"
    case topLeft = "window.top-left", topRight = "window.top-right"
    case bottomLeft = "window.bottom-left", bottomRight = "window.bottom-right"
    case maximize = "window.maximize", center = "window.center"
    case nextDisplay = "window.next-display", previousDisplay = "window.previous-display"
    case restore = "window.restore"

    var title: String {
        switch self {
        case .leftHalf: "Move Window to Left Half"
        case .rightHalf: "Move Window to Right Half"
        case .topHalf: "Move Window to Top Half"
        case .bottomHalf: "Move Window to Bottom Half"
        case .topLeft: "Move Window to Top Left"
        case .topRight: "Move Window to Top Right"
        case .bottomLeft: "Move Window to Bottom Left"
        case .bottomRight: "Move Window to Bottom Right"
        case .maximize: "Maximize Window"
        case .center: "Center Window"
        case .nextDisplay: "Move Window to Next Display"
        case .previousDisplay: "Move Window to Previous Display"
        case .restore: "Restore Previous Window Frame"
        }
    }
}

@MainActor
enum DesktopWindowController {
    private struct WindowKey: Hashable {
        let processIdentifier: pid_t
        let elementHash: UInt
    }

    private static var previousFrames: [WindowKey: CGRect] = [:]
    private static let accessibilityPromptKey = "AXTrustedCheckOptionPrompt" as CFString

    static func permissionStatus(requestIfNeeded: Bool = false) -> AccessibilityPermissionStatus {
        if AXIsProcessTrusted() { return .granted }
        if requestIfNeeded {
            _ = AXIsProcessTrustedWithOptions([accessibilityPromptKey: true] as CFDictionary)
        }
        return .denied
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func perform(_ command: DesktopWindowCommand) -> String? {
        guard permissionStatus(requestIfNeeded: true) == .granted else {
            return "Accessibility access is required. Enable LaunchDeck in System Settings → Privacy & Security → Accessibility, then retry."
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return "No frontmost application is available. Focus another app and retry."
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return "The frontmost app did not expose a movable focused window."
        }
        let window = unsafeBitCast(focused, to: AXUIElement.self)
        guard let currentFrame = frame(of: window) else { return "LaunchDeck could not read the focused window frame." }
        let key = WindowKey(processIdentifier: app.processIdentifier, elementHash: CFHash(window))
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard !screens.isEmpty else { return "No display is available." }
        let screenIndex = bestScreenIndex(forAXFrame: currentFrame, screens: screens)

        let target: CGRect
        if command == .restore {
            guard let saved = previousFrames.removeValue(forKey: key) else {
                return "No previous frame has been recorded for this window."
            }
            target = saved
        } else {
            previousFrames[key] = currentFrame
            let destinationIndex: Int
            switch command {
            case .nextDisplay: destinationIndex = (screenIndex + 1) % screens.count
            case .previousDisplay: destinationIndex = (screenIndex - 1 + screens.count) % screens.count
            default: destinationIndex = screenIndex
            }
            let visible = axFrame(for: screens[destinationIndex].visibleFrame, screens: screens)
            target = targetFrame(for: command, visibleFrame: visible, currentFrame: currentFrame)
        }
        return setFrame(target, on: window)
    }

    static func targetFrame(for command: DesktopWindowCommand, visibleFrame: CGRect, currentFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        switch command {
        case .leftHalf: return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .rightHalf: return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: visibleFrame.height)
        case .topHalf: return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: halfHeight)
        case .bottomHalf: return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: visibleFrame.width, height: halfHeight)
        case .topLeft: return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight: return CGRect(x: visibleFrame.midX, y: visibleFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft: return CGRect(x: visibleFrame.minX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .bottomRight: return CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: halfWidth, height: halfHeight)
        case .maximize: return visibleFrame
        case .center:
            return CGRect(x: visibleFrame.minX + visibleFrame.width * 0.15,
                          y: visibleFrame.minY + visibleFrame.height * 0.15,
                          width: visibleFrame.width * 0.7, height: visibleFrame.height * 0.7)
        case .nextDisplay, .previousDisplay:
            return CGRect(x: visibleFrame.midX - min(currentFrame.width, visibleFrame.width) / 2,
                          y: visibleFrame.midY - min(currentFrame.height, visibleFrame.height) / 2,
                          width: min(currentFrame.width, visibleFrame.width),
                          height: min(currentFrame.height, visibleFrame.height))
        case .restore: return currentFrame
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func setFrame(_ target: CGRect, on window: AXUIElement) -> String? {
        var position = target.origin
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return "LaunchDeck could not encode the requested window frame."
        }
        guard AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success,
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success else {
            return "The frontmost app refused the requested position or size."
        }
        return nil
    }

    private static func bestScreenIndex(forAXFrame frame: CGRect, screens: [NSScreen]) -> Int {
        screens.enumerated().max {
            frame.intersection(axFrame(for: $0.element.frame, screens: screens)).area
                < frame.intersection(axFrame(for: $1.element.frame, screens: screens)).area
        }?.offset ?? 0
    }

    private static func axFrame(for appKitFrame: CGRect, screens: [NSScreen]) -> CGRect {
        let desktopTop = screens.map(\.frame.maxY).max() ?? 0
        return CGRect(x: appKitFrame.minX, y: desktopTop - appKitFrame.maxY,
                      width: appKitFrame.width, height: appKitFrame.height)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
