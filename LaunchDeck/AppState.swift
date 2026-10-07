import AppKit
import Combine
import Foundation
import LaunchDeckCore
import OSLog
import SwiftUI

private nonisolated let appStateLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "AppState")

/// The facade views observe. It owns application discovery and wires the stores and
/// coordinators together; the work itself lives elsewhere:
/// - `AppState+Library`: favorites, hidden apps, launching, recents, grid ordering, folders
/// - `AppState+Search`: local, unified and intent search queries
/// - `AppState+ObjectActions`: object chains, context actions, file operations
/// - `LocalContentCoordinator`, `UnifiedIndexCoordinator`, `RecipeRunCoordinator`
/// - `LayoutController`, `SemanticSearchController`, `ActionController`
/// - pure ranking, sorting and merge rules in LaunchDeckCore
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published var searchQuery: String = ""
    @Published var favorites: Set<String>
    @Published var recents: [RecentLaunch]
    @Published var recentSearchQueries: [String] = []
    @Published var instantSendObjects: [LaunchObject] = []

    let layoutController: LayoutController
    let searchController: SemanticSearchController
    let actionController: ActionController
    let recipeStore: RecipeStore
    let recipeExecutionLogStore: RecipeExecutionLogStore
    let quicklinkStore: QuicklinkStore
    let clipboardStore: ClipboardStore
    let workflowReceiptStore: WorkflowReceiptStore
    let workflowAITranscriptStore: WorkflowAITranscriptStore
    let AIProviderSettings: AIProviderSettingsStore
    let workflowAIService: WorkflowAIService
    let workflowExecutionEngine: WorkflowExecutionEngine
    let fileOperationService = FileOperationService()
    let objectActionPerformer = ObjectActionPerformer()
    let objectUndoManager = UndoManager()
    let snippetStore: SnippetStore
    let extensionStore: ExtensionStore

    /// The local file index (indexed roots and recent documents).
    let localContent: LocalContentCoordinator
    let unifiedIndex = UnifiedIndexCoordinator()
    private let recipeRunner: RecipeRunCoordinator

    var totalAppCount: Int { apps.count }
    var indexedItems: [SearchItem] { localContent.items }
    var searchCatalogRevision: Int { unifiedIndex.revision }

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
    var canUndoObjectAction: Bool { objectUndoManager.canUndo }
    var objectUndoActionName: String { objectUndoManager.undoActionName }

    let favoritesStore: FavoritesStore
    let recentsStore: RecentsStore
    let launchCountStore: LaunchCountStore
    let searchLearningStore: SearchLearningStore
    private var clipboardMonitor: ClipboardMonitor?
    private nonisolated let discoveryService: ApplicationDiscoveryService
    let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()

    var appsByIdentifier: [String: DiscoveredApp] = [:]
    var searchIndex = SearchIndex(apps: [])
    private var cancellables = Set<AnyCancellable>()
    private var directoryMonitor: ApplicationDirectoryMonitor?
    private var discoveryGeneration = 0
    private var discoveryTask: Task<Void, Never>?

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
        self.localContent = LocalContentCoordinator(store: localIndexStore, recentDocumentStore: recentDocumentStore,
                                                    rootPaths: { [preferences] in preferences.indexedRootPaths })
        self.searchLearningStore = SearchLearningStore()
        self.favorites = favoritesStore.load()
        let loadedRecents = recentsStore.load()
        self.recents = loadedRecents
        self.launchCountStore = LaunchCountStore(seedingFrom: loadedRecents)

        let layoutController = LayoutController(layoutStore: layoutStore)
        let searchController = SemanticSearchController()
        let recipeExecutionLogStore = RecipeExecutionLogStore()
        let actionController = ActionController(recipeLogStore: recipeExecutionLogStore)
        let recipeStore = RecipeStore()
        let quicklinkStore = QuicklinkStore()
        let clipboardStore = ClipboardStore()
        let snippetStore = SnippetStore()
        let extensionStore = ExtensionStore()
        let workflowReceiptStore = WorkflowReceiptStore()
        let workflowAITranscriptStore = WorkflowAITranscriptStore()
        let AIProviderSettings = AIProviderSettingsStore()
        let workflowAIService = WorkflowAIService(providerLoader: {
            await MainActor.run { AIProviderSettings.runtimeConfiguration }
        }) { entry in
            await MainActor.run { workflowAITranscriptStore.append(entry) }
        }
        let workflowNodeExecutor = DefaultWorkflowNodeExecutor(AI: workflowAIService)
        let workflowExecutionEngine = WorkflowExecutionEngine(executor: workflowNodeExecutor,
                                                              receiptStore: workflowReceiptStore)
        self.layoutController = layoutController
        self.searchController = searchController
        self.actionController = actionController
        self.recipeStore = recipeStore
        self.recipeExecutionLogStore = recipeExecutionLogStore
        self.quicklinkStore = quicklinkStore
        self.clipboardStore = clipboardStore
        self.snippetStore = snippetStore
        self.extensionStore = extensionStore
        self.workflowReceiptStore = workflowReceiptStore
        self.workflowAITranscriptStore = workflowAITranscriptStore
        self.AIProviderSettings = AIProviderSettings
        self.workflowAIService = workflowAIService
        self.workflowExecutionEngine = workflowExecutionEngine
        self.recipeRunner = RecipeRunCoordinator(workflowExecutionEngine: workflowExecutionEngine,
                                                 actionController: actionController,
                                                 approvedShortcuts: { [preferences] in Set(preferences.approvedShortcuts) })
        self.recentSearchQueries = searchLearningStore.snapshot.recentQueries
        workflowNodeExecutor.instantSendProvider = { [weak self] in self?.instantSendObjects ?? [] }
        workflowNodeExecutor.approvedShortcutsProvider = { [weak self] in Set(self?.preferences.approvedShortcuts ?? []) }

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
        quicklinkStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        clipboardStore.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        snippetStore.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        extensionStore.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        localContent.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        unifiedIndex.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        localContent.itemsChanged = { [weak self] in self?.rebuildUnifiedIndex() }
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
            let index = self.unifiedIndex.index
            let catalog = self.unifiedIndex.catalog
            return await Task.detached(priority: .userInitiated) {
                IntentCandidateSelector.select(query: query, index: index, catalog: catalog,
                                               preferredFallbackIdentifiers: preferredFallbackIDs)
            }.value
        }
        actionController.appProvider = { [weak self] identifier in
            self?.appsByIdentifier[identifier].map { URL(fileURLWithPath: $0.path) }
        }
        actionController.applicationOpened = { [weak self] identifier in
            guard let self, let app = self.appsByIdentifier[identifier] else { return }
            self.updateRecents(with: app)
        }
        actionController.documentOpened = { [weak self] path in
            self?.localContent.recordRecentDocument(path)
        }
        searchController.initialize()
        clipboardMonitor = ClipboardMonitor(store: clipboardStore, preferences: preferences)
        clipboardMonitor?.start()
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
        // Every way the query changes (typing, deep links, programmatic resets) reaches AI search.
        $searchQuery
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] query in self?.searchController.handleQueryChange(query) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { await self?.searchController.refreshAvailability() }
            }
            .store(in: &cancellables)
        // Turning history off also deletes what was already captured.
        preferences.$clipboardEnabled
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in self?.clipboardStore.clear() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.clipboardStore.flush() }
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
        discoveryGeneration += 1
        let requestGeneration = discoveryGeneration
        discoveryTask?.cancel()
        let discoveryService = discoveryService
        let showSystemApps = preferences.showSystemApps
        changedPaths?.forEach { AppIconCache.shared.invalidate(path: $0) }
        let startedAt = ContinuousClock.now
        // The scan does not need AppState; holding it only for the hop back avoids keeping a
        // released AppState alive for the whole disk scan.
        discoveryTask = Task.detached(priority: .userInitiated) { [weak self] in
            let discovered: [DiscoveredApp]
            if let changedPaths {
                discovered = discoveryService.refreshApplications(changedPaths: changedPaths,
                                                                  showSystemApps: showSystemApps)
            } else {
                discovered = discoveryService.discoverApplications(showSystemApps: showSystemApps)
            }
            guard !Task.isCancelled else { return }
            await self?.handleDiscoveredApps(discovered, generation: requestGeneration,
                                              elapsed: startedAt.duration(to: .now))
        }
    }

    private func handleDiscoveredApps(_ discovered: [DiscoveredApp], generation: Int,
                                      elapsed: Duration) {
        guard generation == discoveryGeneration else { return }
        appStateLogger.info("Application discovery completed count=\(discovered.count) duration=\(elapsed.milliseconds, format: .fixed(precision: 1))ms")
        withAnimation(.easeInOut(duration: 0.25)) {
            apps = discovered
        }
        appsByIdentifier = Dictionary(discovered.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        searchIndex = SearchIndex(apps: discovered)
        rebuildUnifiedIndex()
        layoutController.sync(with: discovered)
    }

    // MARK: - Search focus, local content, actions and privacy

    func postSearchFocusRequest() {
        focusPublisher.send()
    }

    func refreshLocalContent(rootPaths: [String]? = nil) {
        localContent.refresh(rootPaths: rootPaths)
    }

    func applyLocalContentChange(_ change: LocalContentChange) {
        localContent.apply(change)
    }

    func addIndexedRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !preferences.indexedRootPaths.contains(path) else { return }
        preferences.indexedRootPaths.append(path)
    }

    func removeIndexedRoot(_ path: String) { preferences.indexedRootPaths.removeAll { $0 == path } }

    func requestAction(_ action: LaunchDeckAction) {
        // Workflow recipes have no legacy steps; every entry point (search, intents, deep links,
        // Settings) must route them through the workflow engine.
        if case .runRecipe(let identifier, _, _) = action,
           let recipe = recipeStore.recipes.first(where: { $0.id == identifier }), recipe.workflow != nil {
            runRecipe(recipe)
            return
        }
        actionController.request(action, approvedShortcuts: Set(preferences.approvedShortcuts))
    }

    /// Runs a saved recipe; see RecipeRunCoordinator.
    func runRecipe(_ recipe: Recipe, values: [String: String]? = nil) {
        recipeRunner.run(recipe, values: values)
    }

    func confirmPendingAction() { actionController.confirmPending() }
    func cancelPendingAction() { actionController.cancelPending() }
    func dismissActionError() { actionController.dismissError() }
    func clearPrivateHistory() {
        clearRecents()
        launchCountStore.clear()
        cachedCollections = nil
        actionController.clearHistory()
        searchLearningStore.clear()
        recentSearchQueries = []
        clipboardStore.clear()
        recipeExecutionLogStore.clear()
        workflowReceiptStore.clear()
        workflowAITranscriptStore.clear()
        fileOperationService.clearRecentDestinations()
        instantSendObjects = []
        localContent.clearHistory()
    }

    struct CollectionOrderingKey: Equatable {
        let sortOption: AppPreferences.SortOption
        let showHiddenApps: Bool
        let hiddenApps: Set<String>
        let layout: [AppCollectionItem]
        let apps: [DiscoveredApp]
        let recents: [RecentLaunch]
        let launchCounts: [String: Int]
    }

    var cachedCollections: (key: CollectionOrderingKey, value: [AppCollectionItem])?

    // MARK: - Private helpers

    private func rebuildUnifiedIndex(approvedShortcuts: [String]? = nil, recipes: [Recipe]? = nil) {
        unifiedIndex.rebuild(apps: apps, indexedItems: indexedItems,
                             approvedShortcuts: approvedShortcuts ?? preferences.approvedShortcuts,
                             recipes: recipes ?? recipeStore.recipes)
    }
}
