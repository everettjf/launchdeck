import AppKit
import Combine
import Foundation
import LaunchDeckCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published private(set) var layout: [AppCollectionItem]
    @Published var searchQuery: String = ""
    @Published private(set) var favorites: Set<String>
    @Published private(set) var recents: [RecentLaunch]
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
        directoryMonitor = ApplicationDirectoryMonitor { [weak self] changedPaths in
            Task { @MainActor [weak self] in
                self?.refreshApps(changedPaths: changedPaths)
            }
        }
        directoryMonitor?.startMonitoring()
    }

    func refreshApps() {
        refreshApps(showSystemApps: preferences.showSystemApps)
    }

    private func refreshApps(changedPaths: [String]) {
        let discoveryService = discoveryService
        let showSystemApps = preferences.showSystemApps
        weak var weakSelf = self
        Task.detached(priority: .userInitiated) {
            let discovered = discoveryService.refreshApplications(
                changedPaths: changedPaths,
                showSystemApps: showSystemApps
            )
            await MainActor.run {
                weakSelf?.handleDiscoveredApps(discovered)
            }
        }
    }

    private func refreshApps(showSystemApps: Bool) {
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
        let updatedLayout = LayoutSynchronizer.sync(layout: layout, with: apps)
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
        let updated = RecentLaunchList.recordingLaunch(of: app, in: recents, maxCount: recentsStore.maxCount)
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

    // Called when search query changes - handles semantic search state
    func handleSearchQueryChange(_ query: String) {
        // Cancel any pending debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // 1. If search is empty, clear AI results
        guard !query.isEmpty else {
            clearSemanticSearch()
            return
        }

        // 2. Check if using AI search (starts with /)
        let useAISearch = query.hasPrefix("/")
        let actualQuery = useAISearch ? String(query.dropFirst()) : query

        // 3. If not using AI search, clear AI results
        if !useAISearch {
            clearSemanticSearch()
            return
        }

        // 4. If only "/" is entered (no actual query), clear AI results
        if actualQuery.isEmpty {
            clearSemanticSearch()
            return
        }

        // 5. If using AI search (/xxx), trigger semantic search with debounce
        if isSemanticSearchAvailable, !actualQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            // Debounce: wait 2 seconds before triggering AI search
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
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
        return SearchRanking.filter(apps, matching: actualQuery,
                                    favorites: favorites, recents: recents, layout: layout)
    }

    private func clearSemanticSearch() {
        // Cancel any debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // Cancel any ongoing search task
        semanticSearchTask?.cancel()

        // Clear the searching state
        isSemanticSearching = false

        // Clear results
        if !semanticSearchResults.isEmpty {
            semanticSearchResults = []
        }
    }

    private func triggerSemanticSearch(query: String) {
        // Cancel any ongoing search
        semanticSearchTask?.cancel()

        isSemanticSearching = true

        semanticSearchTask = Task { @MainActor in
            guard let service = semanticSearchService as? SemanticSearchService else {
                isSemanticSearching = false
                return
            }

            let results = await service.searchApps(apps, query: query)

            // Check if search query hasn't changed
            let currentQuery = self.searchQuery.hasPrefix("/")
                ? String(self.searchQuery.dropFirst())
                : self.searchQuery

            if currentQuery == query && !Task.isCancelled {
                self.updateSemanticResults(results.map { $0.app })
            }

            isSemanticSearching = false
        }
    }

    @Published private(set) var semanticSearchResults: [DiscoveredApp] = []

    private func updateSemanticResults(_ results: [DiscoveredApp]) {
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
            if let dissolved = FolderDissolution.item(for: folder, reusing: layout[index]) {
                layout[index] = dissolved
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

    private func orderedIdentifiers() -> [String] {
        layout.flatMap { $0.containedAppIdentifiers }
    }

    private func defaultFolderName(suggesting identifiers: [String]) -> String {
        FolderNaming.suggestedName(forAppIdentifiers: identifiers, appsByIdentifier: appsByIdentifier)
            ?? NSLocalizedString("New Folder", comment: "Default folder name")
    }

    private func modifyLayout(_ modify: (inout [AppCollectionItem]) -> Void) {
        var updated = layout
        modify(&updated)
        layout = updated
        layoutStore.save(updated)
    }

    private func sortedAppIdentifiers(for option: AppPreferences.SortOption) -> [String] {
        switch option {
        case .custom:
            return orderedIdentifiers()
        case .alphabetical:
            return AppSorting.alphabetical(apps)
        case .mostLaunched:
            return AppSorting.mostLaunched(apps, recents: recents)
        case .recentlyLaunched:
            return AppSorting.recentlyLaunched(apps, recents: recents)
        }
    }
}
