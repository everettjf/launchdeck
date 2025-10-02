import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var layout: [AppCollectionItem]
    @Published var searchQuery: String = ""
    @Published private(set) var favorites: Set<String>
    @Published private(set) var recents: [RecentLaunch]
    @Published var presentedAppInfo: AppInfoData?

    var totalAppCount: Int { apps.count }

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private nonisolated let discoveryService: ApplicationDiscoveryService
    private let layoutStore: LayoutStore
    private let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()

    private var appsByIdentifier: [String: DiscoveredApp] = [:]
    private var cancellables = Set<AnyCancellable>()

    var searchFocusPublisher: AnyPublisher<Void, Never> {
        focusPublisher.eraseToAnyPublisher()
    }

    init(preferences: AppPreferences,
         favoritesStore: FavoritesStore? = nil,
         recentsStore: RecentsStore? = nil,
         discoveryService: ApplicationDiscoveryService? = nil,
         layoutStore: LayoutStore? = nil) {
        self.preferences = preferences
        let favoritesStore = favoritesStore ?? FavoritesStore()
        let recentsStore = recentsStore ?? RecentsStore(maxCount: 12)
        let discoveryService = discoveryService ?? ApplicationDiscoveryService()
        let layoutStore = layoutStore ?? LayoutStore()
        self.favoritesStore = favoritesStore
        self.recentsStore = recentsStore
        self.discoveryService = discoveryService
        self.layoutStore = layoutStore
        self.favorites = favoritesStore.load()
        self.recents = recentsStore.load()
        self.layout = layoutStore.load()

        setupBindings()
        refreshApps()
    }

    private func setupBindings() {
        preferences.$showSystemApps
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshApps()
            }
            .store(in: &cancellables)
    }

    func refreshApps() {
        let includeSystemApps = preferences.showSystemApps
        let discoveryService = discoveryService
        Task.detached(priority: .userInitiated) { [weak self] in
            let discovered = await discoveryService.discoverApplications(includeSystemApps: includeSystemApps)
            await MainActor.run {
                guard let self else { return }
                self.handleDiscoveredApps(discovered)
            }
        }
    }

    private func handleDiscoveredApps(_ discovered: [DiscoveredApp]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            apps = discovered
        }
        appsByIdentifier = Dictionary(uniqueKeysWithValues: discovered.map { ($0.identifier, $0) })
        syncLayoutWithDiscoveredApps()
    }

    private func syncLayoutWithDiscoveredApps() {
        let knownIdentifiers = Set(appsByIdentifier.keys)
        var updatedLayout: [AppCollectionItem] = []

        for item in layout {
            switch item.kind {
            case .app:
                guard let identifier = item.appIdentifier, knownIdentifiers.contains(identifier) else { continue }
                updatedLayout.append(.app(identifier))
            case .folder:
                guard var folder = item.folder else { continue }
                folder.appIdentifiers = folder.appIdentifiers.filter { knownIdentifiers.contains($0) }
                if folder.appIdentifiers.count >= 2 {
                    var folderItem = item
                    folderItem.folder = folder
                    updatedLayout.append(folderItem)
                } else if let singleIdentifier = folder.appIdentifiers.first {
                    updatedLayout.append(.app(singleIdentifier))
                }
            }
        }

        let existingIdentifiers = Set(updatedLayout.flatMap { $0.containedAppIdentifiers })
        let missingIdentifiers = knownIdentifiers.subtracting(existingIdentifiers)
        let sortedMissing = missingIdentifiers
            .compactMap { appsByIdentifier[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for app in sortedMissing {
            updatedLayout.append(.app(app.identifier))
        }

        layout = updatedLayout
        layoutStore.save(updatedLayout)
    }

    func toggleFavorite(for app: DiscoveredApp) {
        if favorites.contains(app.identifier) {
            favorites.remove(app.identifier)
        } else {
            favorites.insert(app.identifier)
        }
        favoritesStore.save(favorites)
        objectWillChange.send()
    }

    func isFavorite(_ app: DiscoveredApp) -> Bool {
        favorites.contains(app.identifier)
    }

    func launch(_ app: DiscoveredApp) {
        let url = URL(fileURLWithPath: app.path)
        let configuration = NSWorkspace.OpenConfiguration()

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] runningApplication, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.presentLaunchError(error, app: app)
                    return
                }
                guard runningApplication != nil else { return }
                self.updateRecents(with: app)
            }
        }
    }

    private func presentLaunchError(_ error: Error, app: DiscoveredApp) {
        let alert = NSAlert()
        alert.messageText = "Unable to open \(app.name)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func revealInFinder(_ app: DiscoveredApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    func copyPathToClipboard(_ app: DiscoveredApp) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(app.path, forType: .string)
    }

    func removeFromRecents(_ app: DiscoveredApp) {
        recents.removeAll { $0.identifier == app.identifier }
        recentsStore.save(recents)
    }

    private func updateRecents(with app: DiscoveredApp) {
        var updated = recents

        if let index = updated.firstIndex(where: { $0.identifier == app.identifier }) {
            var launch = updated.remove(at: index)
            launch.lastLaunch = Date()
            launch.launchCount += 1
            updated.insert(launch, at: 0)
        } else {
            let launch = RecentLaunch(identifier: app.identifier,
                                      displayName: app.name,
                                      path: app.path,
                                      lastLaunch: Date(),
                                      launchCount: 1)
            updated.insert(launch, at: 0)
        }

        if updated.count > recentsStore.maxCount {
            updated = Array(updated.prefix(recentsStore.maxCount))
        }

        recents = updated
        recentsStore.save(updated)
    }

    func clearRecents() {
        recents = []
        recentsStore.save([])
    }

    func postSearchFocusRequest() {
        focusPublisher.send()
    }

    func exportAppCatalog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultExportFileName()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.writeCatalog(to: url)
            }
        }
    }

    func presentAppInfo(for app: DiscoveredApp) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let fileURL = URL(fileURLWithPath: app.path)
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let info = AppInfoData(app: app,
                                   bundleSize: attributes.flatMap { attrs in
                                       guard let size = attrs[.size] as? NSNumber else { return nil }
                                       let formatter = ByteCountFormatter()
                                       formatter.allowedUnits = [.useMB, .useGB]
                                       formatter.countStyle = .file
                                       return formatter.string(fromByteCount: size.int64Value)
                                   },
                                   created: attributes?[.creationDate] as? Date,
                                   modified: attributes?[.modificationDate] as? Date,
                                   permissions: permissionsString(for: fileURL.path))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.12)) {
                    self.presentedAppInfo = info
                }
            }
        }
    }

    func copyDetails(of info: AppInfoData) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.formattedDetails, forType: .string)
    }

    func dismissAppInfo() {
        presentedAppInfo = nil
    }

    func appsMatchingSearch() -> [DiscoveredApp] {
        guard !searchQuery.isEmpty else { return allApps() }
        let term = searchQuery.lowercased()
        let matches = apps.filter { $0.searchableText.contains(term) }
        return matches.sorted { searchRank(for: $0) > searchRank(for: $1) }
    }

    func favoriteApps() -> [DiscoveredApp] {
        orderedIdentifiers().compactMap { identifier in
            guard favorites.contains(identifier) else { return nil }
            return appsByIdentifier[identifier]
        }
    }

    func recentApps() -> [DiscoveredApp] {
        recents.compactMap { launch in
            appsByIdentifier[launch.identifier]
        }
    }

    func allApps() -> [DiscoveredApp] {
        orderedIdentifiers().compactMap { appsByIdentifier[$0] }
    }

    func orderedCollections() -> [AppCollectionItem] {
        switch preferences.sortOption {
        case .custom:
            return layout
        case .alphabetical, .mostLaunched, .recentlyLaunched:
            let identifiers = sortedAppIdentifiers(for: preferences.sortOption)
            return identifiers.map { AppCollectionItem.app($0) }
        }
    }

    func app(for identifier: String) -> DiscoveredApp? {
        appsByIdentifier[identifier]
    }

    func collection(withID id: String) -> AppCollectionItem? {
        layout.first { $0.id == id }
    }

    func createEmptyFolder(named name: String) {
        modifyLayout { layout in
            let folder = AppCollectionItem.folder(name: name, appIdentifiers: [])
            layout.append(folder)
        }
    }

    func renameFolder(id: String, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == id }),
                  layout[index].kind == .folder else { return }
            layout[index].folder?.name = newName
        }
    }

    func moveItem(_ draggedID: String, before targetID: String?) {
        guard draggedID != targetID else { return }
        modifyLayout { layout in
            guard let fromIndex = layout.firstIndex(where: { $0.id == draggedID }) else { return }
            let item = layout.remove(at: fromIndex)
            if let targetID, let targetIndex = layout.firstIndex(where: { $0.id == targetID }) {
                layout.insert(item, at: targetIndex)
            } else {
                layout.append(item)
            }
        }
    }

    func addApp(_ appID: String, toFolder folderID: String) {
        modifyLayout { layout in
            guard layout.contains(where: { $0.id == folderID }) else { return }
            if let appIndex = layout.firstIndex(where: { $0.id == appID }) {
                layout.remove(at: appIndex)
            }
            guard let folderIndex = layout.firstIndex(where: { $0.id == folderID }),
                  var folder = layout[folderIndex].folder else { return }
            guard !folder.appIdentifiers.contains(appID) else { return }
            folder.appIdentifiers.append(appID)
            layout[folderIndex].folder = folder
        }
    }

    func createFolder(byCombining firstID: String, and secondID: String) {
        guard firstID != secondID else { return }
        modifyLayout { layout in
            guard let firstIndex = layout.firstIndex(where: { $0.id == firstID }),
                  let secondIndex = layout.firstIndex(where: { $0.id == secondID }) else { return }
            let firstItem = layout[firstIndex]
            let secondItem = layout[secondIndex]
            guard let firstApp = firstItem.appIdentifier,
                  let secondApp = secondItem.appIdentifier else { return }

            let lowerIndex = min(firstIndex, secondIndex)
            let higherIndex = max(firstIndex, secondIndex)
            layout.remove(at: higherIndex)
            layout.remove(at: lowerIndex)

            let folderName = defaultFolderName(suggesting: [firstApp, secondApp])
            let folder = AppCollectionItem.folder(name: folderName, appIdentifiers: [firstApp, secondApp])
            layout.insert(folder, at: lowerIndex)
        }
    }

    func removeApp(_ appID: String, fromFolder folderID: String) {
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == folderID }),
                  var folder = layout[index].folder else { return }
            folder.appIdentifiers.removeAll { $0 == appID }
            if folder.appIdentifiers.count >= 2 {
                layout[index].folder = folder
            } else if let single = folder.appIdentifiers.first {
                layout[index] = .app(single)
            } else {
                layout.remove(at: index)
            }
        }
    }

    func deleteFolder(_ folderID: String) {
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == folderID }),
                  let folder = layout[index].folder else { return }
            layout.remove(at: index)
            let insertIndex = min(index, layout.count)
            for (offset, identifier) in folder.appIdentifiers.enumerated() {
                layout.insert(.app(identifier), at: insertIndex + offset)
            }
        }
    }

    func dissolveFolderIfNeeded(_ folderID: String) {
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == folderID }),
                  var folder = layout[index].folder else { return }
            folder.appIdentifiers = folder.appIdentifiers.filter { appsByIdentifier[$0] != nil }
            if folder.appIdentifiers.count >= 2 {
                layout[index].folder = folder
            } else if let single = folder.appIdentifiers.first {
                layout[index] = .app(single)
            } else {
                layout.remove(at: index)
            }
        }
    }

    private func orderedIdentifiers() -> [String] {
        layout.flatMap { $0.containedAppIdentifiers }
    }

    private func searchRank(for app: DiscoveredApp) -> Int {
        var weight = 0
        if favorites.contains(app.identifier) {
            weight += 20
        }
        if let firstRecent = recents.first, firstRecent.identifier == app.identifier {
            weight += 10
        }
        if let layoutIndex = layout.firstIndex(where: { $0.containedAppIdentifiers.contains(app.identifier) }) {
            weight += max(0, 15 - layoutIndex)
        }
        if !app.isSystemApp {
            weight += 1
        }
        return weight
    }

    private func defaultFolderName(suggesting identifiers: [String]) -> String {
        let categories = identifiers.compactMap { appsByIdentifier[$0]?.category }
        if let common = categories.mostCommonElement() {
            return common
        }
        return NSLocalizedString("New Folder", comment: "Default folder name")
    }

    private func modifyLayout(_ modify: (inout [AppCollectionItem]) -> Void) {
        var updated = layout
        modify(&updated)
        layout = updated
        layoutStore.save(updated)
    }

    private func writeCatalog(to url: URL) async {
        let exportApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let recentsLookup = Dictionary(uniqueKeysWithValues: recents.map { ($0.identifier, $0) })

        let payload = exportApps.map { app -> ExportedApp in
            let recent = recentsLookup[app.identifier]
            return ExportedApp(name: app.name,
                               bundleIdentifier: app.bundleIdentifier,
                               path: app.path,
                               category: app.category,
                               version: app.bundleVersion,
                               developer: app.developer,
                               isSystemApp: app.isSystemApp,
                               keywords: app.keywords.sorted(),
                               lastLaunch: recent?.lastLaunch,
                               launchCount: recent?.launchCount ?? 0)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if #available(macOS 13.0, *) {
                encoder.dateEncodingStrategy = .iso8601
            } else {
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    let formatter = ISO8601DateFormatter()
                    let string = formatter.string(from: date)
                    var container = encoder.singleValueContainer()
                    try container.encode(string)
                }
            }
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            presentExportError(error.localizedDescription)
        }
    }

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: Date())
        return "ApplicationCatalog_\(timestamp).json"
    }

    nonisolated private func permissionsString(for path: String) -> String? {
        var components: [String] = []
        if FileManager.default.isReadableFile(atPath: path) { components.append("Read") }
        if FileManager.default.isWritableFile(atPath: path) { components.append("Write") }
        if FileManager.default.isExecutableFile(atPath: path) { components.append("Execute") }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    private func presentExportError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = message
        alert.runModal()
    }

    private func sortedAppIdentifiers(for option: AppPreferences.SortOption) -> [String] {
        let allApps = apps
        let recentsLookup = Dictionary(uniqueKeysWithValues: recents.map { ($0.identifier, $0) })

        switch option {
        case .custom:
            return orderedIdentifiers()
        case .alphabetical:
            return allApps
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { $0.identifier }
        case .mostLaunched:
            return allApps
                .sorted { first, second in
                    let firstCount = recentsLookup[first.identifier]?.launchCount ?? 0
                    let secondCount = recentsLookup[second.identifier]?.launchCount ?? 0
                    if firstCount == secondCount {
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                    return firstCount > secondCount
                }
                .map { $0.identifier }
        case .recentlyLaunched:
            return allApps
                .sorted { first, second in
                    let firstDate = recentsLookup[first.identifier]?.lastLaunch
                    let secondDate = recentsLookup[second.identifier]?.lastLaunch
                    switch (firstDate, secondDate) {
                    case let (lhs?, rhs?):
                        if lhs == rhs {
                            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                        }
                        return lhs > rhs
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                    }
                }
                .map { $0.identifier }
        }
    }
}

private extension Array where Element == String {
    func mostCommonElement() -> String? {
        guard !isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for element in self {
            counts[element, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }
}

private struct ExportedApp: Codable {
    let name: String
    let bundleIdentifier: String?
    let path: String
    let category: String?
    let version: String?
    let developer: String?
    let isSystemApp: Bool
    let keywords: [String]
    let lastLaunch: Date?
    let launchCount: Int
}

struct AppInfoData: Identifiable {
    let app: DiscoveredApp
    let bundleSize: String?
    let created: Date?
    let modified: Date?
    let permissions: String?

    var id: String { app.identifier }

    var formattedDetails: String {
        var lines: [String] = []
        lines.append("Name: \(app.name)")
        if let bundleIdentifier = app.bundleIdentifier {
            lines.append("Bundle Identifier: \(bundleIdentifier)")
        }
        if let version = app.bundleVersion {
            lines.append("Version: \(version)")
        }
        if let developer = app.developer {
            lines.append("Developer: \(developer)")
        }
        if let category = app.category {
            lines.append("Category: \(category)")
        }
        lines.append("System Application: \(app.isSystemApp ? "Yes" : "No")")
        lines.append("Path: \(app.path)")
        if let bundleSize {
            lines.append("Bundle Size: \(bundleSize)")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let created {
            lines.append("Created: \(formatter.string(from: created))")
        }
        if let modified {
            lines.append("Last Modified: \(formatter.string(from: modified))")
        }
        if let permissions {
            lines.append("Permissions: \(permissions)")
        }
        if !app.keywords.isEmpty {
            lines.append("Keywords: \(app.keywords.sorted().joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
