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
              let text = pasteboard.string(forType: .string) else { return }
        store.record(text, retentionHours: preferences.clipboardRetentionHours)
    }
}
