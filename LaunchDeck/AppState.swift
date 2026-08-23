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
    @Published private(set) var indexedItems: [SearchItem] = []

    let layoutController: LayoutController
    let searchController: SemanticSearchController
    let actionController: ActionController
    let recipeStore: RecipeStore

    var totalAppCount: Int { apps.count }

    // MARK: - Forwarded state from controllers

    var layout: [AppCollectionItem] { layoutController.layout }
    var isSemanticSearching: Bool { searchController.isSearching }
    var semanticSearchResults: [DiscoveredApp] {
        searchController.results.compactMap { result in
            guard result.targetIdentifier.hasPrefix("application:") else { return nil }
            return appsByIdentifier[String(result.targetIdentifier.dropFirst("application:".count))]
        }
    }
    var intentResults: [IntentRecommendation] { searchController.results }
    var intentSearchPhase: IntentSearchPhase { searchController.phase }
    var intentSearchAvailability: IntentSearchAvailability { searchController.availability }
    var pendingAction: LaunchDeckAction? { actionController.pendingAction }
    var pendingActionPreview: ActionPreview? { actionController.pendingPreview }
    var actionError: String? { actionController.lastError }
    var isSemanticSearchAvailable: Bool { searchController.isAvailable }

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private let localIndexStore: LocalIndexStore
    private let recentDocumentStore: RecentDocumentStore
    private nonisolated let discoveryService: ApplicationDiscoveryService
    private let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()

    private var appsByIdentifier: [String: DiscoveredApp] = [:]
    private var searchIndex = SearchIndex(apps: [])
    private var unifiedSearchIndex = UnifiedSearchIndex(items: [])
    private var searchItemsByIdentifier: [String: SearchItem] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var directoryMonitor: ApplicationDirectoryMonitor?
    private var localIndexGeneration = 0

    var searchFocusPublisher: AnyPublisher<Void, Never> {
        focusPublisher.eraseToAnyPublisher()
    }

    init(preferences: AppPreferences,
         favoritesStore: FavoritesStore? = nil,
         recentsStore: RecentsStore? = nil,
         discoveryService: ApplicationDiscoveryService? = nil,
         layoutStore: LayoutStore? = nil,
         localIndexStore: LocalIndexStore = LocalIndexStore(),
         recentDocumentStore: RecentDocumentStore = RecentDocumentStore()) {
        self.preferences = preferences
        let favoritesStore = favoritesStore ?? FavoritesStore()
        let recentsStore = recentsStore ?? RecentsStore(maxCount: 12)
        let discoveryService = discoveryService ?? ApplicationDiscoveryService()
        let layoutStore = layoutStore ?? LayoutStore()
        self.favoritesStore = favoritesStore
        self.recentsStore = recentsStore
        self.discoveryService = discoveryService
        self.localIndexStore = localIndexStore
        self.recentDocumentStore = recentDocumentStore
        self.favorites = favoritesStore.load()
        self.recents = recentsStore.load()

        let layoutController = LayoutController(layoutStore: layoutStore)
        let searchController = SemanticSearchController()
        let actionController = ActionController()
        let recipeStore = RecipeStore()
        self.layoutController = layoutController
        self.searchController = searchController
        self.actionController = actionController
        self.recipeStore = recipeStore

        // Forward controller changes so views observing AppState stay live
        layoutController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        searchController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        actionController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recipeStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        recipeStore.$recipes
            .dropFirst()
            .sink { [weak self] recipes in self?.rebuildUnifiedIndex(recipes: recipes) }
            .store(in: &cancellables)

        setupBindings()
        setupDirectoryMonitoring()
        refreshApps()

        searchController.candidatesProvider = { [weak self] query in
            guard let self else { return [] }
            let preferredFallbackIDs = self.allApps().map { "application:\($0.identifier)" }
                + self.indexedItems.map(\.id)
            return IntentCandidateSelector.select(query: query, index: self.unifiedSearchIndex,
                                                  catalog: self.searchItemsByIdentifier,
                                                  preferredFallbackIdentifiers: preferredFallbackIDs)
        }
        actionController.appProvider = { [weak self] identifier in
            self?.appsByIdentifier[identifier].map { URL(fileURLWithPath: $0.path) }
        }
        actionController.applicationOpened = { [weak self] identifier in
            guard let self, let app = self.appsByIdentifier[identifier] else { return }
            self.updateRecents(with: app)
        }
        actionController.documentOpened = { [weak self] path in
            self?.recordRecentDocument(path)
        }
        searchController.initialize()
        refreshLocalContent()
    }

    private func setupBindings() {
        preferences.$showSystemApps
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshApps()
            }
            .store(in: &cancellables)
        preferences.$indexedRootPaths
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] paths in self?.refreshLocalContent(rootPaths: paths) }
            .store(in: &cancellables)
        preferences.$approvedShortcuts
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] shortcuts in self?.rebuildUnifiedIndex(approvedShortcuts: shortcuts) }
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
        searchIndex = SearchIndex(apps: discovered)
        rebuildUnifiedIndex()
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
        actionController.request(.openApplication(identifier: app.identifier, name: app.name))
    }

    private func presentLaunchError(_ error: Error, app: DiscoveredApp) {
        let alert = NSAlert()
        alert.messageText = "Unable to open \(app.name)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func revealInFinder(_ app: DiscoveredApp) {
        actionController.request(.revealApplication(identifier: app.identifier, name: app.name))
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

        return localRankedResults(for: actualQuery).map(\.app)
    }

    func searchItems(matching query: String, limit: Int = 80) -> [SearchItem] {
        unifiedSearchIndex.search(query, kindBoosts: [.application: 0.04, .project: 0.03], limit: limit).map(\.item)
    }

    func searchItem(identifier: String) -> SearchItem? { searchItemsByIdentifier[identifier] }

    func perform(_ item: SearchItem) {
        if let recommendation = intentResults.first(where: { $0.targetIdentifier == item.id }) {
            let appName: String?
            if case .application(let identifier, _) = item.target { appName = appsByIdentifier[identifier]?.name }
            else { appName = nil }
            switch IntentActionResolver.resolve(recommendation, target: item, applicationName: appName,
                                                installedApplications: appsByIdentifier.mapValues { $0.name },
                                                recipes: recipeStore.recipes) {
            case .action(let action):
                requestAction(action)
                return
            case .missingParameters(let missing):
                actionController.presentError("This action needs: \(missing.joined(separator: ", ")). Refine the intent or choose a concrete target.")
                return
            case .unresolved:
                actionController.presentError("The suggested action could not be resolved safely.")
                return
            }
        }
        let action: LaunchDeckAction?
        switch item.target {
        case .application(let identifier, _):
            action = appsByIdentifier[identifier].map { .openApplication(identifier: identifier, name: $0.name) }
        case .file(let path): action = .openFile(path: path, applicationIdentifier: nil, applicationName: nil)
        case .folder(let path), .project(let path): action = .openProject(path: path)
        case .registeredAction(let identifier):
            if identifier == "open.terminal" {
                action = .openTerminal(directory: FileManager.default.homeDirectoryForCurrentUser.path)
            } else {
                action = nil
                actionController.presentError("“\(identifier)” needs a concrete target. Use intent search or select a file, project, app, or recipe.")
            }
        case .systemSetting(let identifier):
            action = SystemSettingsDestination(rawValue: identifier).map { .openSystemSettings(destination: $0) }
        case .shortcut(let name): action = .runShortcut(name: name)
        case .recipe(let identifier):
            action = recipeStore.recipes.first(where: { $0.id == identifier }).map { .runRecipe(identifier: $0.id, name: $0.name, steps: $0.steps) }
        }
        if let action { requestAction(action) }
    }

    func refreshLocalContent(rootPaths: [String]? = nil) {
        localIndexGeneration += 1
        let requestGeneration = localIndexGeneration
        let rootPaths = rootPaths ?? preferences.indexedRootPaths
        if let cached = localIndexStore.load(expectedRootPaths: rootPaths) {
            indexedItems = cached.items
            rebuildUnifiedIndex()
        }
        let roots = rootPaths.map(URL.init(fileURLWithPath:))
        let storedRecentURLs = recentDocumentStore.load().map { URL(fileURLWithPath: $0.path) }
        Task.detached(priority: .utility) { [weak self] in
            let items = LocalContentIndexer().index(configuration: .init(roots: roots), recentURLs: storedRecentURLs)
            await MainActor.run {
                guard let self, requestGeneration == self.localIndexGeneration else { return }
                self.indexedItems = items
                self.rebuildUnifiedIndex()
                try? self.localIndexStore.save(LocalIndexSnapshot(rootPaths: rootPaths, items: items))
            }
        }
    }

    func addIndexedRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !preferences.indexedRootPaths.contains(path) else { return }
        preferences.indexedRootPaths.append(path)
    }

    func removeIndexedRoot(_ path: String) { preferences.indexedRootPaths.removeAll { $0 == path } }

    func intentReason(for app: DiscoveredApp) -> String? {
        intentResults.first { $0.targetIdentifier == "application:\(app.identifier)" }?.reason
    }

    func intentDetail(for item: SearchItem) -> String? {
        guard let result = intentResults.first(where: { $0.targetIdentifier == item.id }) else { return nil }
        let percent = Int((result.confidence * 100).rounded())
        let actionName = ActionRegistry.shared.descriptors.first { $0.id == result.actionIdentifier }?.title
            ?? result.actionIdentifier
        let appName: String?
        if case .application(let identifier, _) = item.target { appName = appsByIdentifier[identifier]?.name }
        else { appName = nil }
        let resolution = IntentActionResolver.resolve(result, target: item, applicationName: appName,
                                                      installedApplications: appsByIdentifier.mapValues { $0.name },
                                                      recipes: recipeStore.recipes)
        let missing: String
        if case .missingParameters(let values) = resolution { missing = " · Needs \(values.joined(separator: ", "))" }
        else if case .unresolved = resolution { missing = " · Unresolved" }
        else { missing = "" }
        return "\(result.reason) · \(percent)% · \(actionName)\(missing)"
    }

    func requestAction(_ action: LaunchDeckAction) {
        actionController.request(action, approvedShortcuts: Set(preferences.approvedShortcuts))
    }
    func confirmPendingAction() { actionController.confirmPending() }
    func cancelPendingAction() { actionController.cancelPending() }
    func dismissActionError() { actionController.dismissError() }
    func clearPrivateHistory() {
        clearRecents()
        actionController.clearHistory()
        try? recentDocumentStore.clear()
        try? localIndexStore.clear()
        indexedItems = []
        rebuildUnifiedIndex()
        refreshLocalContent()
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

    private func localRankedResults(for query: String, limit: Int? = nil) -> [(app: DiscoveredApp, score: Double)] {
        searchIndex.search(query, favorites: favorites, recents: recents,
                           layout: layout, limit: limit)
    }

    private func rebuildUnifiedIndex(approvedShortcuts: [String]? = nil, recipes: [Recipe]? = nil) {
        let items = SearchCatalogBuilder.build(apps: apps, indexedItems: indexedItems,
                                               approvedShortcuts: approvedShortcuts ?? preferences.approvedShortcuts,
                                               recipes: recipes ?? recipeStore.recipes)
        searchItemsByIdentifier = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        unifiedSearchIndex = UnifiedSearchIndex(items: items)
    }

    private func recordRecentDocument(_ path: String) {
        _ = try? recentDocumentStore.record(path: path)
        refreshLocalContent()
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
