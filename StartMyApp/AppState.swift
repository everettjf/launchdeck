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
    @Published private(set) var isSemanticSearching: Bool = false

    var totalAppCount: Int { apps.count }
    var isSemanticSearchAvailable: Bool {
        return semanticSearchService != nil
    }

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private nonisolated let discoveryService: ApplicationDiscoveryService
    private let layoutStore: LayoutStore
    private let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()
    private var semanticSearchService: Any? // SemanticSearchService for macOS 26+

    private var appsByIdentifier: [String: DiscoveredApp] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var semanticSearchTask: Task<Void, Never>?
    private var debounceTimer: Timer?
    private var directoryMonitor: ApplicationDirectoryMonitor?

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
        setupDirectoryMonitoring()
        refreshApps()
        initializeSemanticSearch()
    }

    private func initializeSemanticSearch() {
        Task {
            let service = await SemanticSearchService()
            await MainActor.run {
                self.semanticSearchService = service
            }
        }
    }

    private func setupBindings() {
        preferences.$showSystemApps
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.refreshApps(showSystemApps: newValue)
            }
            .store(in: &cancellables)
    }

    private func setupDirectoryMonitoring() {
        directoryMonitor = ApplicationDirectoryMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshApps()
            }
        }
        directoryMonitor?.startMonitoring()
    }

    func refreshApps() {
        refreshApps(showSystemApps: preferences.showSystemApps)
    }

    private func refreshApps(showSystemApps: Bool) {
        print("refresh apps with show system app: \(showSystemApps)")
        let discoveryService = discoveryService
        weak var weakSelf = self
        Task.detached(priority: .userInitiated) {
            let discovered = await discoveryService.discoverApplications(showSystemApps: showSystemApps)
            await MainActor.run {
                guard let appState = weakSelf else { return }
                appState.handleDiscoveredApps(discovered)
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

    func hideApp(_ app: DiscoveredApp) {
        preferences.hiddenApps.insert(app.identifier)
        objectWillChange.send()
    }

    func unhideApp(_ app: DiscoveredApp) {
        preferences.hiddenApps.remove(app.identifier)
        objectWillChange.send()
    }

    func isHidden(_ app: DiscoveredApp) -> Bool {
        preferences.hiddenApps.contains(app.identifier)
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

    func presentLearn(for app: DiscoveredApp) {
        LearnWindowController.shared.show(for: app)
    }

    // Called when search query changes - handles semantic search state
    func handleSearchQueryChange(_ query: String) {
        print("\n📝 Search query changed to: '\(query)'")

        // Cancel any pending debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // 1. If search is empty, clear AI results
        guard !query.isEmpty else {
            print("   ↳ Query is empty, clearing semantic search")
            clearSemanticSearch()
            return
        }

        // 2. Check if using AI search (starts with /)
        let useAISearch = query.hasPrefix("/")
        let actualQuery = useAISearch ? String(query.dropFirst()) : query

        // 3. If not using AI search, clear AI results
        if !useAISearch {
            print("   ↳ Not using AI search, clearing semantic results")
            clearSemanticSearch()
            return
        }

        // 4. If only "/" is entered (no actual query), clear AI results
        if actualQuery.isEmpty {
            print("   ↳ Only '/' entered, clearing semantic results")
            clearSemanticSearch()
            return
        }

        // 5. If using AI search (/xxx), trigger semantic search with debounce
        if isSemanticSearchAvailable, !actualQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            print("   ↳ AI search mode - debouncing for 2 seconds...")
            print("   ↳ Query to search: '\(actualQuery)'")

            // Debounce: wait 2 seconds before triggering AI search
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("\n⏰ Debounce timer fired! Triggering AI search for: '\(actualQuery)'")
                Task { @MainActor in
                    self.triggerSemanticSearch(query: actualQuery)
                }
            }
        }
    }

    func appsMatchingSearch() -> [DiscoveredApp] {
        // This is now a pure function without side effects
        guard !searchQuery.isEmpty else {
            return allApps()
        }

        // Check if using AI search
        let useAISearch = searchQuery.hasPrefix("/")
        let actualQuery = useAISearch ? String(searchQuery.dropFirst()) : searchQuery

        // If only "/" is entered, return empty
        if useAISearch && actualQuery.isEmpty {
            return []
        }

        // If using AI search, return empty (results come from semanticSearchResults)
        if useAISearch {
            return []
        }

        // Otherwise, use keyword-based search
        let term = actualQuery.lowercased()
        let matches = apps.filter { $0.searchableText.contains(term) }
        return matches.sorted { searchRank(for: $0) > searchRank(for: $1) }
    }

    private func clearSemanticSearch() {
        print("   🧹 Clearing semantic search")

        // Cancel any debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // Cancel any ongoing search task
        semanticSearchTask?.cancel()

        // Clear the searching state
        if isSemanticSearching {
            print("   ↳ Stopping search in progress")
            isSemanticSearching = false
        }

        // Clear results
        if !semanticSearchResults.isEmpty {
            print("   ↳ Clearing \(semanticSearchResults.count) previous results")
            semanticSearchResults = []
        }
    }

    private func triggerSemanticSearch(query: String) {
        print("\n🚀 Triggering semantic search for: '\(query)'")

        // Cancel any ongoing search
        semanticSearchTask?.cancel()

        isSemanticSearching = true
        print("   ↳ Setting isSemanticSearching = true")

        semanticSearchTask = Task { @MainActor in
            guard let service = semanticSearchService as? SemanticSearchService else {
                print("   ❌ Semantic search service not available")
                isSemanticSearching = false
                return
            }

            print("   ⏳ Calling AI service...")
            let results = await service.searchApps(apps, query: query)

            // Check if search query hasn't changed
            let currentQuery = self.searchQuery.hasPrefix("/")
                ? String(self.searchQuery.dropFirst())
                : self.searchQuery

            print("   📊 Got \(results.count) results from AI")
            print("   🔍 Current query: '\(currentQuery)', Search query: '\(query)'")

            if currentQuery == query && !Task.isCancelled {
                print("   ✅ Query matches, updating results")
                self.updateSemanticResults(results.map { $0.app })
            } else {
                print("   ⚠️ Query changed or task cancelled, discarding results")
            }

            isSemanticSearching = false
            print("   ↳ Setting isSemanticSearching = false")
        }
    }

    @Published private(set) var semanticSearchResults: [DiscoveredApp] = []

    private func updateSemanticResults(_ results: [DiscoveredApp]) {
        print("   💾 Updating semantic results: \(results.count) apps")
        for (index, app) in results.prefix(5).enumerated() {
            print("      \(index + 1). \(app.name)")
        }
        if results.count > 5 {
            print("      ... and \(results.count - 5) more")
        }
        semanticSearchResults = results
        objectWillChange.send()
    }

    func favoriteApps() -> [DiscoveredApp] {
        orderedIdentifiers().compactMap { identifier in
            guard favorites.contains(identifier) else { return nil }
            guard let app = appsByIdentifier[identifier] else { return nil }
            if !preferences.showHiddenApps && preferences.hiddenApps.contains(identifier) {
                return nil
            }
            return app
        }
    }

    func recentApps() -> [DiscoveredApp] {
        recents.compactMap { launch in
            guard let app = appsByIdentifier[launch.identifier] else { return nil }
            if !preferences.showHiddenApps && preferences.hiddenApps.contains(launch.identifier) {
                return nil
            }
            return app
        }
    }

    func allApps() -> [DiscoveredApp] {
        orderedIdentifiers().compactMap { identifier in
            guard let app = appsByIdentifier[identifier] else { return nil }
            if !preferences.showHiddenApps && preferences.hiddenApps.contains(identifier) {
                return nil
            }
            return app
        }
    }

    func orderedCollections() -> [AppCollectionItem] {
        let collections: [AppCollectionItem]
        switch preferences.sortOption {
        case .custom:
            collections = layout
        case .alphabetical, .mostLaunched, .recentlyLaunched:
            let identifiers = sortedAppIdentifiers(for: preferences.sortOption)
            collections = identifiers.map { AppCollectionItem.app($0) }
        }

        // Filter hidden apps if showHiddenApps is false
        if preferences.showHiddenApps {
            return collections
        } else {
            return collections.compactMap { item in
                switch item.kind {
                case .app:
                    guard let identifier = item.appIdentifier else { return nil }
                    if preferences.hiddenApps.contains(identifier) {
                        return nil
                    }
                    return item
                case .folder:
                    guard var folder = item.folder else { return nil }
                    // Filter hidden apps from folder
                    folder.appIdentifiers = folder.appIdentifiers.filter { !preferences.hiddenApps.contains($0) }
                    if folder.appIdentifiers.isEmpty {
                        return nil
                    }
                    var filteredItem = item
                    filteredItem.folder = folder
                    return filteredItem
                }
            }
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

        let payload = exportApps.map { app -> ExportedApp in
            return ExportedApp(name: app.name,
                               bundleIdentifier: app.bundleIdentifier,
                               path: app.path,
                               category: app.category,
                               version: app.bundleVersion,
                               developer: app.developer,
                               isSystemApp: app.isSystemApp)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
        return "StartMyApp_Applications_\(timestamp).json"
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

    enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier = "bundle_identifier"
        case path
        case category
        case version
        case developer
        case isSystemApp = "is_system_app"
    }
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
