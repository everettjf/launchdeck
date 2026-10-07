import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry]
    private let fileURL: URL
    private let maximumCount: Int
    private let maximumImageBytes: Int
    private let writeQueue = DispatchQueue(label: "com.everettjf.launchdeck.clipboard-store", qos: .utility)
    private var pendingWrite: DispatchWorkItem?
    static let legacyDefaultsKey = "clipboard.entries.v1"

    /// History lives in Application Support rather than UserDefaults: it can hold megabytes of
    /// images, and is encoded and written off the main thread.
    init(fileURL: URL? = nil, legacyDefaults: UserDefaults = .standard,
         maximumCount: Int = 200, maximumImageBytes: Int = 50_000_000) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.maximumCount = maximumCount
        self.maximumImageBytes = maximumImageBytes
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            entries = decoded
        } else if let data = legacyDefaults.data(forKey: Self.legacyDefaultsKey),
                  let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            entries = decoded
            persist()
        } else {
            entries = []
        }
        legacyDefaults.removeObject(forKey: Self.legacyDefaultsKey)
    }

    func record(_ text: String, retentionHours: Int = 168, now: Date = .now) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        record(.text(text), sourceBundleIdentifier: nil, retentionHours: retentionHours, now: now)
    }

    func record(_ content: ClipboardEntry.Content, sourceBundleIdentifier: String?, retentionHours: Int = 168, now: Date = .now) {
        let entry = ClipboardEntry(content: content, copiedAt: now, sourceBundleIdentifier: sourceBundleIdentifier)
        guard entries.first?.content != entry.content else { return }
        var updated = entries
        updated.removeAll { $0.copiedAt < Self.cutoff(retentionHours: retentionHours, now: now) }
        updated.insert(entry, at: 0)
        updated = Array(updated.prefix(maximumCount))
        entries = Self.limitingImageBytes(updated, to: maximumImageBytes)
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
        let cutoff = Self.cutoff(retentionHours: retentionHours, now: now)
        guard entries.contains(where: { $0.copiedAt < cutoff }) else { return }
        entries.removeAll { $0.copiedAt < cutoff }
        persist()
    }

    func remove(id: UUID) { entries.removeAll { $0.id == id }; persist() }

    func clear() {
        entries = []
        pendingWrite?.cancel()
        pendingWrite = nil
        let fileURL = fileURL
        writeQueue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Blocks until queued writes reach disk. Used at termination and by tests.
    func flush() {
        if let pendingWrite {
            self.pendingWrite = nil
            pendingWrite.perform()
        }
        writeQueue.sync {}
    }

    private func persist() {
        pendingWrite?.cancel()
        let snapshot = entries
        let fileURL = fileURL
        let writeQueue = writeQueue
        // The item is dispatched to the write queue only after the debounce, so a burst of
        // copies costs one encode. `flush()` can still run it synchronously.
        let work = DispatchWorkItem {
            writeQueue.async {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.pendingWrite === work else { return }
            self.pendingWrite = nil
            work.perform()
        }
    }

    private static func cutoff(retentionHours: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(retentionHours) * 3600)
    }

    /// Keeps the newest images within the byte budget; text and file entries are always kept.
    private static func limitingImageBytes(_ entries: [ClipboardEntry], to budget: Int) -> [ClipboardEntry] {
        var used = 0
        return entries.filter { entry in
            guard case .image(let data) = entry.content else { return true }
            used += data.count
            return used <= budget
        }
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LaunchDeck", isDirectory: true)
            .appendingPathComponent("clipboard-history-v1.json")
    }
}

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private let preferences: AppPreferences
    private var timer: Timer?
    private var purgeTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private static var isRecordingSuspended = false
    private static var ignoredThroughChangeCount = Int.min

    static let builtInSensitiveBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.apple.Passwords", "com.apple.keychainaccess"
    ]

    /// Markers from nspasteboard.org that password managers and other apps set on content
    /// that must not be stored in clipboard history.
    static let privatePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword")
    ]

    init(store: ClipboardStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
    }

    /// Pasteboard changes LaunchDeck makes itself (such as a capture's synthetic Cmd+C and the
    /// restore that follows) are not user copies and stay out of history.
    static func suspendRecording() { isRecordingSuspended = true }

    static func resumeRecording(ignoringThrough changeCount: Int) {
        ignoredThroughChangeCount = max(ignoredThroughChangeCount, changeCount)
        isRecordingSuspended = false
    }

    static func shouldRecord(types: [NSPasteboard.PasteboardType]?, sourceBundleIdentifier: String?,
                             excludedBundleIdentifiers: Set<String>) -> Bool {
        if let types, types.contains(where: privatePasteboardTypes.contains) { return false }
        guard let sourceBundleIdentifier else { return false }
        return !builtInSensitiveBundleIDs.contains(sourceBundleIdentifier)
            && !excludedBundleIdentifiers.contains(sourceBundleIdentifier)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        purgeExpired()
        purgeTimer?.invalidate()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
    }

    private func purgeExpired() {
        store.purge(retentionHours: preferences.clipboardRetentionHours)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard !Self.isRecordingSuspended, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard pasteboard.changeCount > Self.ignoredThroughChangeCount,
              preferences.clipboardEnabled else { return }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard Self.shouldRecord(types: pasteboard.types, sourceBundleIdentifier: bundleID,
                                excludedBundleIdentifiers: preferences.clipboardExcludedBundleIdentifiers),
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
