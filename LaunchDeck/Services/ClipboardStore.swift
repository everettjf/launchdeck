import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]
    private let defaults: UserDefaults
    private let key = "clipboard.entries.v1"
    private let maximumCount: Int

    init(defaults: UserDefaults = .standard, maximumCount: Int = 200) {
        self.defaults = defaults
        self.maximumCount = maximumCount
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ClipboardEntry].self, from: $0) } ?? []
    }

    func record(_ text: String, retentionHours: Int = 168, now: Date = .now) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, entries.first?.text != text else { return }
        purge(retentionHours: retentionHours, now: now)
        entries.insert(ClipboardEntry(text: text, copiedAt: now), at: 0)
        entries = Array(entries.prefix(maximumCount))
        persist()
    }

    func record(_ content: ClipboardEntry.Content, sourceBundleIdentifier: String?, retentionHours: Int = 168, now: Date = .now) {
        let entry = ClipboardEntry(content: content, copiedAt: now, sourceBundleIdentifier: sourceBundleIdentifier)
        guard entries.first?.content != entry.content else { return }
        purge(retentionHours: retentionHours, now: now)
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(maximumCount))
        persist()
    }

    func writeToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general; pasteboard.clearContents()
        switch entry.content {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .image(let data): pasteboard.setData(data, forType: .png)
        case .files(let paths): pasteboard.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        }
    }

    func paste(_ entry: ClipboardEntry) {
        writeToPasteboard(entry)
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    func purge(retentionHours: Int, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(retentionHours) * 3600)
        entries.removeAll { $0.copiedAt < cutoff }
        persist()
    }

    func remove(id: UUID) { entries.removeAll { $0.id == id }; persist() }
    func clear() { entries = []; defaults.removeObject(forKey: key) }
    private func persist() { defaults.set(try? JSONEncoder().encode(entries), forKey: key) }
}

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private let preferences: AppPreferences
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    static let builtInSensitiveBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass"
    ]

    init(store: ClipboardStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard preferences.clipboardEnabled,
              let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              !Self.builtInSensitiveBundleIDs.contains(bundleID),
              !preferences.clipboardExcludedBundleIdentifiers.contains(bundleID),
              let content = content(from: pasteboard) else { return }
        store.record(content, sourceBundleIdentifier: bundleID, retentionHours: preferences.clipboardRetentionHours)
    }

    private func content(from pasteboard: NSPasteboard) -> ClipboardEntry.Content? {
        if let URLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !URLs.isEmpty {
            return .files(URLs.map(\.path))
        }
        if let data = pasteboard.data(forType: .png), !data.isEmpty { return .image(data) }
        if let tiff = pasteboard.data(forType: .tiff),
           let representation = NSBitmapImageRep(data: tiff),
           let png = representation.representation(using: .png, properties: [:]), !png.isEmpty {
            return .image(png)
        }
        if let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(value) }
        return nil
    }
}
