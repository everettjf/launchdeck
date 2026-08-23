import AppKit
import Foundation

@MainActor
enum InstantSendService {
    static func capture(completion: @escaping ([LaunchObject]) -> Void) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let objects = scriptedObjects(frontmost: frontmost), !objects.isEmpty {
            completion(objects)
            return
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        postCopyShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pasteboard.changeCount != previousChangeCount else {
                completion([])
                return
            }
            completion(objects(from: pasteboard, sourceBundleIdentifier: frontmost?.bundleIdentifier))
        }
    }

    static func objects(from pasteboard: NSPasteboard = .general,
                        sourceBundleIdentifier: String? = nil) -> [LaunchObject] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return urls.map { url in
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                let kind: LaunchObject.Kind = exists && isDirectory.boolValue ? .folder : .file
                return LaunchObject(kind: kind, title: url.lastPathComponent, value: url.path,
                                    applicationIdentifier: sourceBundleIdentifier)
            }
        }
        if let value = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            if let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
                return [LaunchObject(kind: .url, title: url.host ?? value, value: value,
                                     applicationIdentifier: sourceBundleIdentifier)]
            }
            return [LaunchObject(kind: .text, title: String(value.prefix(80)), value: value,
                                 applicationIdentifier: sourceBundleIdentifier)]
        }
        return []
    }

    private static func scriptedObjects(frontmost: NSRunningApplication?) -> [LaunchObject]? {
        guard let bundleID = frontmost?.bundleIdentifier else { return nil }
        if bundleID == "com.apple.finder" {
            let source = "tell application \"Finder\" to get POSIX path of every item of selection"
            guard let descriptor = execute(source), descriptor.numberOfItems > 0 else { return nil }
            return (1...descriptor.numberOfItems).compactMap { index in
                guard let path = descriptor.atIndex(index)?.stringValue else { return nil }
                var directory: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                return LaunchObject(kind: directory.boolValue ? .folder : .file,
                                    title: URL(fileURLWithPath: path).lastPathComponent, value: path,
                                    applicationIdentifier: bundleID)
            }
        }
        let source: String?
        switch bundleID {
        case "com.apple.Safari": source = "tell application \"Safari\" to get URL of current tab of front window"
        case "com.google.Chrome": source = "tell application \"Google Chrome\" to get URL of active tab of front window"
        default: source = nil
        }
        guard let source, let value = execute(source)?.stringValue,
              let url = URL(string: value) else { return nil }
        return [LaunchObject(kind: .url, title: url.host ?? value, value: value, applicationIdentifier: bundleID)]
    }

    private static func postCopyShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func execute(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
