import AppKit
import Combine
import Foundation
import LaunchDeckCore
import OSLog
import SwiftUI

private nonisolated let appStateLogger = Logger(subsystem: "com.everettjf.launchdeck", category: "AppState")

private nonisolated struct UnifiedIndexSnapshot: Sendable {
    let catalog: [String: SearchItem]
    let index: UnifiedSearchIndex

    init(items: [SearchItem]) {
        catalog = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        index = UnifiedSearchIndex(items: items)
    }
}

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
    @Published private(set) var recentSearchQueries: [String] = []
    @Published private(set) var instantSendObjects: [LaunchObject] = []
    @Published private(set) var searchCatalogRevision = 0

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
    private let fileOperationService = FileOperationService()
    private let objectActionPerformer = ObjectActionPerformer()
    private let objectUndoManager = UndoManager()
    let snippetStore: SnippetStore
    let extensionStore: ExtensionStore

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
    var canUndoObjectAction: Bool { objectUndoManager.canUndo }
    var objectUndoActionName: String { objectUndoManager.undoActionName }

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private let localIndexStore: LocalIndexStore
    private let recentDocumentStore: RecentDocumentStore
    private let searchLearningStore: SearchLearningStore
    private var clipboardMonitor: ClipboardMonitor?
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
    private var discoveryGeneration = 0
    private var unifiedIndexGeneration = 0
    private var discoveryTask: Task<Void, Never>?
    private var localIndexTask: Task<Void, Never>?
    private var unifiedIndexTask: Task<Void, Never>?

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
        self.searchLearningStore = SearchLearningStore()
        self.favorites = favoritesStore.load()
        self.recents = recentsStore.load()

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
        discoveryTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let discovered: [DiscoveredApp]
            if let changedPaths {
                discovered = discoveryService.refreshApplications(changedPaths: changedPaths,
                                                                  showSystemApps: showSystemApps)
            } else {
                discovered = discoveryService.discoverApplications(showSystemApps: showSystemApps)
            }
            guard !Task.isCancelled else { return }
            await self.handleDiscoveredApps(discovered, generation: requestGeneration,
                                             elapsed: startedAt.duration(to: .now))
        }
    }

    private func handleDiscoveredApps(_ discovered: [DiscoveredApp], generation: Int,
                                      elapsed: Duration) {
        guard generation == discoveryGeneration else { return }
        appStateLogger.info("Application discovery completed count=\(discovered.count) duration=\(Self.milliseconds(elapsed), format: .fixed(precision: 1))ms")
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

    func receiveInstantSend(_ objects: [LaunchObject]) {
        instantSendObjects = objects
    }

    func clearInstantSend() { instantSendObjects = [] }

    func objectTargets(for action: ObjectAction) -> [LaunchObject] {
        switch action {
        case .move:
            let recent = fileOperationService.recentDestinationPaths.map {
                LaunchObject(kind: .folder, title: URL(fileURLWithPath: $0).lastPathComponent, value: $0)
            }
            let indexed = indexedItems.compactMap(LaunchObject.init(searchItem:)).filter { $0.kind == .folder }
            var seen = Set<String>()
            return (recent + indexed).filter { seen.insert($0.value).inserted }
        case .openWith:
            return allApps().map {
                LaunchObject(kind: .application, title: $0.name, value: $0.path, applicationIdentifier: $0.identifier)
            }
        default: return []
        }
    }

    func perform(_ action: ObjectAction, sources: [LaunchObject], target: LaunchObject?) {
        guard !sources.isEmpty else { return }
        if action == .saveAsRecipe {
            saveObjectChainAsRecipe(sources: sources, target: target)
            return
        }
        guard let kind = recipeKind(for: action) else { return }
        let clipboardEntries = sources.compactMap { source -> ClipboardEntry? in
            guard source.kind == .clipboard, let id = UUID(uuidString: source.value) else { return nil }
            return clipboardStore.entries.first { $0.id == id }
        }
        if clipboardEntries.count == sources.count, let first = clipboardEntries.first, [.copy, .paste].contains(action) {
            if action == .paste { clipboardStore.paste(first) } else { clipboardStore.writeToPasteboard(first) }
            return
        }
        let targetValue: String?
        if action == .paste { targetValue = sources.first?.applicationIdentifier }
        else { targetValue = target?.value }
        do {
            if let undo = try objectActionPerformer.execute(kind: kind, sources: sources.map(\.value), target: targetValue) {
                objectUndoManager.registerUndo(withTarget: self) { state in state.undoObjectAction(undo) }
                objectUndoManager.setActionName(undo.title)
            }
            refreshLocalContent()
        } catch { actionController.presentError(error.localizedDescription) }
    }

    func undoLastObjectAction() {
        guard objectUndoManager.canUndo else { return }
        objectUndoManager.undo()
    }

    private func undoObjectAction(_ record: FileUndoRecord) {
        do { try fileOperationService.undo(record); refreshLocalContent() }
        catch { actionController.presentError("Undo failed: \(error.localizedDescription)") }
    }

    private func saveObjectChainAsRecipe(sources: [LaunchObject], target: LaunchObject?) {
        guard let name = prompt(title: "Save Action Chain", message: "Recipe name:", value: "Object Workflow") else { return }
        // The saved default is an open chain; the navigator replaces this with its selected action when supplied.
        let recipe = Recipe(name: name, steps: [.objectAction(.open, sources: sources.map(\.value), target: target?.value)])
        do { try recipeStore.save(recipe) }
        catch { actionController.presentError(error.localizedDescription) }
    }

    func saveObjectChainAsRecipe(action: ObjectAction, sources: [LaunchObject], target: LaunchObject?) {
        guard let kind = recipeKind(for: action),
              let name = prompt(title: "Save Action Chain", message: "Recipe name:", value: "\(action.title) Workflow") else { return }
        let savedTarget = action == .paste ? (target?.value ?? sources.first?.applicationIdentifier) : target?.value
        let recipe = Recipe(name: name, steps: [.objectAction(kind, sources: sources.map(\.value), target: savedTarget)])
        do { try recipeStore.save(recipe) }
        catch { actionController.presentError(error.localizedDescription) }
    }

    private func recipeKind(for action: ObjectAction) -> RecipeStep.ObjectActionKind? {
        switch action {
        case .open: .open
        case .reveal: .reveal
        case .copy: .copy
        case .paste: .paste
        case .openWith: .openWith
        case .move: .move
        case .duplicate: .duplicate
        case .compress: .compress
        case .trash: .trash
        case .saveAsRecipe: nil
        }
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
        let parsed = SearchQuery.parse(query)
        let searchableText = parsed.text
        let utilityCandidates = searchableText.isEmpty ? [] : (UtilitySearchProvider.results(for: searchableText, quicklinks: quicklinkStore.quicklinks)
            + DesktopSearchProvider.items(matching: searchableText,
                                          clipboardEnabled: preferences.clipboardEnabled,
                                          clipboardEntries: clipboardStore.entries,
                                          snippets: snippetStore.snippets)
            + extensionStore.searchItems(matching: searchableText))
        let utilities = utilityCandidates.filter(parsed.matches)
        let ranked = unifiedSearchIndex.search(parsed,
                                               kindBoosts: [.application: 0.04, .project: 0.03],
                                               itemBoosts: searchLearningStore.boosts(for: parsed.text),
                                               limit: limit).map(\.item)
        return Array((utilities + ranked).prefix(limit))
    }

    func searchItem(identifier: String) -> SearchItem? { searchItemsByIdentifier[identifier] }

    func contextualActions(for item: SearchItem) -> [SearchContextAction] {
        SearchContextActionCatalog.actions(for: item)
    }

    func perform(_ contextAction: SearchContextAction, on item: SearchItem) {
        switch contextAction {
        case .open:
            perform(item)
        case .reveal:
            reveal(item)
        case .quickLook:
            guard let path = item.fileSystemPath else { return }
            QuickLookCoordinator.shared.preview(path: path)
        case .copyPath:
            guard let path = item.fileSystemPath else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        case .openTerminal:
            guard let path = item.fileSystemPath else { return }
            var isDirectory: ObjCBool = false
            let directory = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                ? path : URL(fileURLWithPath: path).deletingLastPathComponent().path
            requestAction(.openTerminal(directory: directory))
        case .rename:
            guard let url = item.fileSystemURL,
                  let name = prompt(title: "Rename \(url.lastPathComponent)", message: "Enter a new name:", value: url.lastPathComponent) else { return }
            runFileOperation { _ = try fileOperationService.rename(url, to: name) }
        case .move:
            guard let url = item.fileSystemURL else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Move Here"
            if let recent = fileOperationService.recentDestinationPaths.first {
                panel.directoryURL = URL(fileURLWithPath: recent)
            }
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            runFileOperation { _ = try fileOperationService.move([url], to: destination) }
        case .duplicate:
            guard let url = item.fileSystemURL else { return }
            runFileOperation { _ = try fileOperationService.duplicate(url) }
        case .compress:
            guard let url = item.fileSystemURL else { return }
            runFileOperation { _ = try fileOperationService.compress(url) }
        case .tag:
            guard let url = item.fileSystemURL,
                  let value = prompt(title: "Set Finder Tags", message: "Enter comma-separated tags:", value: "") else { return }
            runFileOperation {
                try fileOperationService.setTags(value.split(separator: ",").map(String.init), on: [url])
            }
        case .trash:
            guard let url = item.fileSystemURL else { return }
            let alert = NSAlert()
            alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
            alert.informativeText = "The item can be recovered from the Trash."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            runFileOperation { try fileOperationService.moveToTrash([url]) }
        case .paste:
            guard case .clipboardEntry(let identifier) = item.target,
                  let entry = clipboardStore.entries.first(where: { $0.id == identifier }) else { return }
            clipboardStore.paste(entry)
        }
    }

    private func runFileOperation(_ operation: () throws -> Void) {
        do {
            try operation()
            refreshLocalContent()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func prompt(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: value)
        field.frame = CGRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func reveal(_ item: SearchItem) {
        switch item.target {
        case .application(let identifier, _):
            guard let app = appsByIdentifier[identifier] else { return }
            requestAction(.revealApplication(identifier: identifier, name: app.name))
        default:
            guard let path = item.fileSystemPath else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func perform(_ item: SearchItem) {
        let learningQuery = searchQuery.hasPrefix("/") ? String(searchQuery.dropFirst()) : searchQuery
        searchLearningStore.record(query: learningQuery, itemID: item.id)
        recentSearchQueries = searchLearningStore.snapshot.recentQueries
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
            if let recipe = recipeStore.recipes.first(where: { $0.id == identifier }), recipe.workflow != nil {
                let workflow = recipe.resolvedWorkflow
                var values: [String: String] = [:]
                for variable in workflow.variables {
                    guard let value = prompt(title: "Run \(workflow.name)",
                                             message: "Value for \(variable.name) (\(variable.valueType.rawValue)):",
                                             value: variable.defaultValue) else { return }
                    values[variable.name] = value
                }
                let preview = workflowExecutionEngine.dryRun(workflow)
                guard preview.isReady else {
                    actionController.presentError(preview.issues.first(where: { $0.severity == .error })?.message ?? "The workflow is invalid.")
                    return
                }
                if workflow.policy.requiresDryRunBeforeMutation, preview.requiresConfirmation {
                    let alert = NSAlert()
                    alert.messageText = "Run “\(workflow.name)”?"
                    alert.informativeText = "Mutations: \(preview.mutations.joined(separator: ", "))\nTools: \(preview.requiredTools.sorted().joined(separator: ", "))"
                    alert.addButton(withTitle: "Run")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                Task { [weak self] in
                    guard let self else { return }
                    let receipt = await self.workflowExecutionEngine.run(workflow, variableValues: values)
                    if !receipt.succeeded {
                        self.actionController.presentError(receipt.nodes.last?.error ?? "The workflow could not run.")
                    }
                }
                action = nil
            } else {
                action = recipeStore.recipes.first(where: { $0.id == identifier }).map { .runRecipe(identifier: $0.id, name: $0.name, steps: $0.steps) }
            }
        case .copyText(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            action = nil
        case .url(let url): action = .openURL(url)
        case .systemCommand(let identifier):
            if let command = DesktopWindowCommand(rawValue: identifier),
               let error = DesktopWindowController.perform(command) { actionController.presentError(error) }
            action = nil
        case .clipboardEntry(let identifier):
            if let entry = clipboardStore.entries.first(where: { $0.id == identifier }) { clipboardStore.writeToPasteboard(entry) }
            action = nil
        }
        if let action { requestAction(action) }
    }

    func refreshLocalContent(rootPaths: [String]? = nil) {
        localIndexGeneration += 1
        let requestGeneration = localIndexGeneration
        localIndexTask?.cancel()
        let rootPaths = rootPaths ?? preferences.indexedRootPaths
        let roots = rootPaths.map(URL.init(fileURLWithPath:))
        let localIndexStore = localIndexStore
        let recentDocumentStore = recentDocumentStore
        localIndexTask = Task.detached(priority: .utility) { [weak self] in
            if let cached = localIndexStore.load(expectedRootPaths: rootPaths) {
                guard !Task.isCancelled else { return }
                await self?.applyIndexedItems(cached.items, generation: requestGeneration, source: "cache")
            }

            let startedAt = ContinuousClock.now
            let storedRecentURLs = recentDocumentStore.load().map { URL(fileURLWithPath: $0.path) }
            let items = LocalContentIndexer().index(configuration: .init(roots: roots),
                                                    recentURLs: storedRecentURLs,
                                                    isCancelled: { Task.isCancelled })
            guard !Task.isCancelled else { return }
            do {
                try localIndexStore.save(LocalIndexSnapshot(rootPaths: rootPaths, items: items))
            } catch {
                appStateLogger.error("Local index cache save failed: \(error.localizedDescription, privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            await self?.applyIndexedItems(items, generation: requestGeneration, source: "scan",
                                          elapsed: startedAt.duration(to: .now))
        }
    }

    private func applyIndexedItems(_ items: [SearchItem], generation: Int, source: String,
                                   elapsed: Duration? = nil) {
        guard generation == localIndexGeneration else { return }
        indexedItems = items
        rebuildUnifiedIndex()
        if let elapsed {
            appStateLogger.info("Local index \(source, privacy: .public) completed count=\(items.count) duration=\(Self.milliseconds(elapsed), format: .fixed(precision: 1))ms")
        } else {
            appStateLogger.info("Local index cache restored count=\(items.count)")
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
        searchLearningStore.clear()
        recentSearchQueries = []
        clipboardStore.clear()
        recipeExecutionLogStore.clear()
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
        let apps = apps
        let indexedItems = indexedItems
        let approvedShortcuts = approvedShortcuts ?? preferences.approvedShortcuts
        let recipes = recipes ?? recipeStore.recipes
        unifiedIndexGeneration += 1
        let requestGeneration = unifiedIndexGeneration
        unifiedIndexTask?.cancel()
        let startedAt = ContinuousClock.now
        unifiedIndexTask = Task.detached(priority: .userInitiated) { [weak self] in
            let items = SearchCatalogBuilder.build(apps: apps, indexedItems: indexedItems,
                                                   approvedShortcuts: approvedShortcuts,
                                                   recipes: recipes)
            let snapshot = UnifiedIndexSnapshot(items: items)
            guard !Task.isCancelled else { return }
            await self?.applyUnifiedIndex(snapshot, generation: requestGeneration,
                                          elapsed: startedAt.duration(to: .now))
        }
    }

    private func applyUnifiedIndex(_ snapshot: UnifiedIndexSnapshot, generation: Int,
                                   elapsed: Duration) {
        guard generation == unifiedIndexGeneration else { return }
        searchItemsByIdentifier = snapshot.catalog
        unifiedSearchIndex = snapshot.index
        searchCatalogRevision &+= 1
        appStateLogger.debug("Unified index built count=\(snapshot.catalog.count) duration=\(Self.milliseconds(elapsed), format: .fixed(precision: 1))ms")
    }

    nonisolated private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
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

private extension SearchItem {
    var fileSystemURL: URL? { fileSystemPath.map { URL(fileURLWithPath: $0) } }
}
