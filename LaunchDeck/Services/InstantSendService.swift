import AppKit
import Foundation

@MainActor
enum InstantSendService {
    /// Captures the frontmost app's selection. Finder, Safari and Chrome are read through
    /// Apple Events; other apps receive a synthetic Cmd+C whose result is read and then
    /// replaced with the user's previous clipboard so the shortcut never clobbers it.
    static func capture(completion: @escaping ([LaunchObject]) -> Void) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        guard let source = scriptSource(for: bundleID) else {
            captureByCopying(sourceBundleIdentifier: bundleID, completion: completion)
            return
        }
        Task { @MainActor in
            let output = await runAppleScript(source)
            if let output, let objects = scriptedObjects(output: output, bundleID: bundleID), !objects.isEmpty {
                completion(objects)
            } else {
                captureByCopying(sourceBundleIdentifier: bundleID, completion: completion)
            }
        }
    }

    private static func captureByCopying(sourceBundleIdentifier: String?,
                                         completion: @escaping ([LaunchObject]) -> Void) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let previousChangeCount = pasteboard.changeCount
        ClipboardMonitor.suspendRecording()
        postCopyShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            defer { ClipboardMonitor.resumeRecording(ignoringThrough: pasteboard.changeCount) }
            guard pasteboard.changeCount != previousChangeCount else {
                completion([])
                return
            }
            let objects = objects(from: pasteboard, sourceBundleIdentifier: sourceBundleIdentifier)
            snapshot.restore(to: pasteboard)
            completion(objects)
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

    private static func scriptSource(for bundleID: String?) -> String? {
        switch bundleID {
        case "com.apple.finder":
            // One POSIX path per line keeps parsing independent of AppleScript list formatting.
            return """
            set output to ""
            tell application "Finder" to set theSelection to selection as alias list
            repeat with theItem in theSelection
                set output to output & POSIX path of theItem & linefeed
            end repeat
            return output
            """
        case "com.apple.Safari": return "tell application \"Safari\" to get URL of current tab of front window"
        case "com.google.Chrome": return "tell application \"Google Chrome\" to get URL of active tab of front window"
        default: return nil
        }
    }

    private static func scriptedObjects(output: String, bundleID: String?) -> [LaunchObject]? {
        if bundleID == "com.apple.finder" {
            return output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }.map { path in
                var directory: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                return LaunchObject(kind: directory.boolValue ? .folder : .file,
                                    title: URL(fileURLWithPath: path).lastPathComponent, value: path,
                                    applicationIdentifier: bundleID)
            }
        }
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value) else { return nil }
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

    /// Runs the script in `osascript` so a slow or unresponsive target app can never block
    /// the main thread. Returns nil on failure, denial or timeout.
    private static func runAppleScript(_ source: String, timeout: TimeInterval = 2) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let resumed = OneShot()
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
                if resumed.claim() { continuation.resume(returning: text) }
            }
            do {
                try process.run()
            } catch {
                if resumed.claim() { continuation.resume(returning: nil) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard resumed.claim() else { return }
                process.terminate()
                continuation.resume(returning: nil)
            }
        }
    }
}

private nonisolated final class OneShot: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// A full copy of every item and type on a pasteboard, used to put the user's clipboard back.
@MainActor
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type] = data }
            }
            return values
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
