import AppKit
import Combine
import Foundation
import LaunchDeckCore
import SwiftUI

/// Orchestrates the app: discovery, favorites, recents, and launch actions.
/// Layout mutations live in LayoutController, AI search in SemanticSearchController,
/// and pure ranking/sorting/merge rules in LaunchDeckCore.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published var searchQuery: String = ""
    @Published private(set) var favorites: Set<String>
    @Published private(set) var recents: [RecentLaunch]

    let layoutController: LayoutController
    let searchController: SemanticSearchController

    var totalAppCount: Int { apps.count }

    // MARK: - Forwarded state from controllers

    var layout: [AppCollectionItem] { layoutController.layout }
    var isSemanticSearching: Bool { searchController.isSearching }
    var semanticSearchResults: [DiscoveredApp] { searchController.results }
    var isSemanticSearchAvailable: Bool { searchController.isAvailable }

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private nonisolated let discoveryService: ApplicationDiscoveryService
    private let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()

    private var appsByIdentifier: [String: DiscoveredApp] = [:]
    private var cancellables = Set<AnyCancellable>()
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
        self.favorites = favoritesStore.load()
        self.recents = recentsStore.load()

        let layoutController = LayoutController(layoutStore: layoutStore)
        let searchController = SemanticSearchController()
        self.layoutController = layoutController
        self.searchController = searchController

        // Forward controller changes so views observing AppState stay live
        layoutController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        searchController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        setupBindings()
        setupDirectoryMonitoring()
        refreshApps()

        searchController.appsProvider = { [weak self] in self?.apps ?? [] }
        searchController.initialize()
    }

    private func setupBindings() {
        preferences.$showSystemApps
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshApps()
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
        refreshApps(changedPaths: nil)
    }

    private func refreshApps(changedPaths: [String]?) {
        let discoveryService = discoveryService
        let showSystemApps = preferences.showSystemApps
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let discovered: [DiscoveredApp]
            if let changedPaths {
                discovered = discoveryService.refreshApplications(changedPaths: changedPaths,
                                                                  showSystemApps: showSystemApps)
            } else {
                discovered = discoveryService.discoverApplications(showSystemApps: showSystemApps)
            }
            await self.handleDiscoveredApps(discovered)
        }
    }

    private func handleDiscoveredApps(_ discovered: [DiscoveredApp]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            apps = discovered
        }
        appsByIdentifier = Dictionary(uniqueKeysWithValues: discovered.map { ($0.identifier, $0) })
        layoutController.sync(with: discovered)
    }

    // MARK: - Favorites & hidden apps

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

    // MARK: - Launching

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

    // MARK: - Recents

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

    // MARK: - Search

    func postSearchFocusRequest() {
        focusPublisher.send()
    }

    // Called when search query changes - handles semantic search state
    func handleSearchQueryChange(_ query: String) {
        searchController.handleQueryChange(query)
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

    // MARK: - App queries

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

    // MARK: - Layout façade (delegates to LayoutController)

    func collection(withID id: String) -> AppCollectionItem? {
        layoutController.collection(withID: id)
    }

    func createEmptyFolder(named name: String) {
        layoutController.createEmptyFolder(named: name)
    }

    func renameFolder(id: String, to newName: String) {
        layoutController.renameFolder(id: id, to: newName)
    }

    func moveItem(_ draggedID: String, before targetID: String?) {
        layoutController.moveItem(draggedID, before: targetID)
    }

    func addApp(_ appID: String, toFolder folderID: String) {
        layoutController.addApp(appID, toFolder: folderID)
    }

    func createFolder(byCombining firstID: String, and secondID: String) {
        let identifiers = [firstID, secondID]
        let folderName = FolderNaming.suggestedName(forAppIdentifiers: identifiers,
                                                    appsByIdentifier: appsByIdentifier)
            ?? NSLocalizedString("New Folder", comment: "Default folder name")
        layoutController.createFolder(byCombining: firstID, and: secondID, named: folderName)
    }

    func removeApp(_ appID: String, fromFolder folderID: String) {
        layoutController.removeApp(appID, fromFolder: folderID)
    }

    func deleteFolder(_ folderID: String) {
        layoutController.deleteFolder(folderID)
    }

    // MARK: - Private helpers

    private func orderedIdentifiers() -> [String] {
        layoutController.orderedIdentifiers
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
