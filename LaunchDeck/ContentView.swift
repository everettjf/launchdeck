import AppKit
import Combine
import SwiftUI
import LaunchDeckCore

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow

    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText: String = ""
    @State private var focusCancellable: AnyCancellable?
    @State private var didAppear = false
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""
    @State private var searchSelection = SearchSelection()
    @State private var pendingRecipe: Recipe?
    @State private var actionPanelItem: SearchItem?
    @State private var selectedKinds = Set(SearchItemKind.allCases)
    @State private var selectedObjectIDs = Set<String>()
    @State private var objectActionRequest: ObjectActionRequest?
    @State private var isLibraryExpanded = false
    @State private var isCommandPressed = false
    @State private var unifiedResults: [SearchItem] = []
    @State private var searchTask: Task<Void, Never>?

    private func makeUnifiedResults() async -> [SearchItem] {
        let query = searchText.hasPrefix("/") ? String(searchText.dropFirst()) : searchText
        guard !query.isEmpty else { return [] }
        let kinds = selectedKinds
        let local = await appState.searchItems(matching: query).filter { kinds.contains($0.kind) }
        guard searchText.hasPrefix("/"), !appState.intentResults.isEmpty else { return local }
        let recommended = appState.intentResults.compactMap { appState.searchItem(identifier: $0.targetIdentifier) }
        let IDs = Set(recommended.map(\.id))
        return recommended + local.filter { !IDs.contains($0.id) }
    }

    private var favoriteApps: [DiscoveredApp] {
        appState.favoriteApps()
    }

    private var recentApps: [DiscoveredApp] {
        appState.recentApps()
    }

    private var launcherRecentApps: [DiscoveredApp] {
        Array(recentApps.prefix(5))
    }

    private var allApps: [DiscoveredApp] {
        appState.allApps()
    }

    private var isCompactHome: Bool {
        searchText.isEmpty && !isLibraryExpanded
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
            mainContent
        }
        .onAppear(perform: configure)
        .onDisappear { focusCancellable?.cancel(); searchTask?.cancel() }
        .onChange(of: searchText) { _, newValue in
            if appState.searchQuery != newValue {
                appState.searchQuery = newValue
            }
            refreshSearchResults()
        }
        .onReceive(appState.$searchQuery.removeDuplicates()) { incoming in
            if searchText != incoming {
                searchText = incoming
            }
        }
        .onChange(of: selectedKinds) { refreshSearchResults() }
        .onChange(of: appState.searchCatalogRevision) { refreshSearchResults() }
        .onChange(of: appState.intentResults.map(\.id)) { refreshSearchResults() }
        .animation(.spring(response: 0.65, dampingFraction: 0.82), value: didAppear)
        .sheet(item: pendingPreviewBinding) { preview in
            ActionPreviewView(preview: preview,
                              onCancel: appState.cancelPendingAction,
                              onConfirm: appState.confirmPendingAction)
        }
        .sheet(item: $pendingRecipe) { recipe in
            RecipeRunView(recipe: recipe) { values in
                run(recipe, values: values)
            }
        }
        .sheet(item: $actionPanelItem) { item in
            SearchActionPanel(
                item: item,
                actions: appState.contextualActions(for: item),
                onRun: { action in
                    actionPanelItem = nil
                    appState.perform(action, on: item)
                }
            )
        }
        .sheet(item: $objectActionRequest) { request in
            ObjectActionNavigatorView(initialSources: request.sources,
                                      availableTargets: appState.objectTargets,
                                      onExecute: appState.perform,
                                      onSaveRecipe: appState.saveObjectChainAsRecipe)
        }
        .sheet(isPresented: Binding(get: { !preferences.hasCompletedOnboarding }, set: { _ in })) {
            OnboardingView().environmentObject(appState).environmentObject(preferences)
        }
        .alert("Action Failed", isPresented: actionErrorBinding) {
            Button("OK") { appState.dismissActionError() }
        } message: {
            Text(appState.actionError ?? "")
        }
        .onOpenURL { url in
            guard let id = RecipeTrigger.recipeID(from: url),
                  let recipe = appState.recipeStore.recipes.first(where: { $0.id == id }) else {
                appState.actionController.presentError("The Recipe link is invalid or no longer installed.")
                return
            }
            if recipe.variables.isEmpty { run(recipe, values: [:]) }
            else { pendingRecipe = recipe }
        }
        .onChange(of: appState.instantSendObjects) { _, objects in
            guard !objects.isEmpty else { return }
            objectActionRequest = ObjectActionRequest(sources: objects)
            appState.clearInstantSend()
        }
        .background(ModifierKeyObserver(isCommandPressed: $isCommandPressed))
    }

    private var mainContent: some View {
        VStack(spacing: isCompactHome ? 10 : 0) {
            VStack(spacing: 0) {
                launcherToolbar
                    .padding(isCompactHome
                        ? EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                        : EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .background {
                        if !isCompactHome {
                            Rectangle().fill(.thickMaterial)
                        }
                    }

                Divider().opacity(0.25)

                if isCompactHome {
                    CompactLauncherRecents(recentApps: launcherRecentApps,
                                           onLaunch: appState.launch)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 28) {
                            if searchText.isEmpty {
                                libraryContent
                            } else if unifiedResults.isEmpty {
                                ContentUnavailableView("No Results",
                                                       systemImage: "magnifyingglass",
                                                       description: Text(noResultsMessage))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 36)
                            } else {
                                UnifiedSearchResultsView(items: unifiedResults,
                                                         selectedIdentifier: searchSelection.selectedIdentifier,
                                                         includedIdentifiers: selectedObjectIDs,
                                                         reason: appState.intentDetail,
                                                         isCommandPressed: isCommandPressed,
                                                         onToggleIncluded: toggleObjectSelection,
                                                         onRun: runSearchItem) {
                                    searchProgressLabel
                                }
                            }
                        }
                        .padding(16)
                    }
                    LauncherKeyboardFooter(isSearching: !searchText.isEmpty,
                                           isSemanticSearching: appState.isSemanticSearching)
                }
            }
            .background {
                if isCompactHome {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                if isCompactHome {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                }
            }

            if isCompactHome {
                LauncherQuickActions(onShowLibrary: showLibrary,
                                     onInstantSend: captureInstantSend,
                                     onOpenRecipeStudio: { openWindow(id: "recipe-studio") })
            }
        }
        .padding(isCompactHome ? 14 : 0)
        .opacity(didAppear ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                didAppear = true
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            NewFolderSheet(isPresented: $isCreatingFolder,
                           folderName: $newFolderName,
                           onCreate: { name in
                               appState.createEmptyFolder(named: name)
                           })
        }
    }

    private var launcherToolbar: some View {
        HStack(spacing: 12) {
            searchField
                .frame(maxWidth: .infinity)

            if !searchText.isEmpty {
                SearchKindFilterMenu(selectedKinds: $selectedKinds)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        isLibraryExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isLibraryExpanded ? "chevron.backward" : "square.grid.2x2")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .help(isLibraryExpanded ? "Back to launcher" : "Browse applications")
            }

            if appState.canUndoObjectAction {
                Button {
                    appState.undoLastObjectAction()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo \(appState.objectUndoActionName)")
            }

            launcherMenu
        }
    }

    private var launcherMenu: some View {
        Menu {
            Button("Instant Send", systemImage: "paperplane", action: captureInstantSend)
            Button("Recipe Studio", systemImage: "square.stack.3d.up") {
                openWindow(id: "recipe-studio")
            }
            Divider()
            Button("Refresh Applications", systemImage: "arrow.clockwise", action: appState.refreshApps)
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .help("More actions")
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            LibraryHeader(appCount: appState.totalAppCount,
                          sortOption: $preferences.sortOption,
                          onRefresh: appState.refreshApps,
                          onNewFolder: beginCreatingFolder)
            if !favoriteApps.isEmpty {
                AppGridSection(title: "Favorites", apps: favoriteApps)
            }
            if preferences.showRecentApps && !recentApps.isEmpty {
                AppGridSection(title: "Recently Launched", apps: recentApps, trailing: {
                    Button("Clear", action: appState.clearRecents)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                })
            }
            allApplicationsSection
        }
    }

    private var searchProgressLabel: some View {
        HStack(spacing: 8) {
            if appState.isSemanticSearching {
                ProgressView().controlSize(.small)
                Text("Understanding intent…")
            } else {
                Text(searchStatusText)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if !appState.recentSearchQueries.isEmpty {
                Menu {
                    ForEach(appState.recentSearchQueries, id: \.self) { query in
                        Button(query) { searchText = query }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Recent searches")
            }
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($isSearchFieldFocused)
                .onSubmit(launchTopResult)
                .onKeyPress(.upArrow) {
                    searchSelection.move(by: -1, items: unifiedResults)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    searchSelection.move(by: 1, items: unifiedResults)
                    return .handled
                }
                .onKeyPress(.space) {
                    guard let item = searchSelection.selectedItem(in: unifiedResults),
                          appState.contextualActions(for: item).contains(.quickLook) else { return .ignored }
                    appState.perform(.quickLook, on: item)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          let item = searchSelection.selectedItem(in: unifiedResults),
                          appState.contextualActions(for: item).contains(.reveal) else { return .ignored }
                    appState.perform(.reveal, on: item)
                    return .handled
                }
                .onKeyPress("k", phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          let item = searchSelection.selectedItem(in: unifiedResults) else { return .ignored }
                    let selected = unifiedResults.filter { selectedObjectIDs.contains($0.id) }.compactMap(LaunchObject.init(searchItem:))
                    let fallback = LaunchObject(searchItem: item).map { [$0] } ?? []
                    if !(selected.isEmpty ? fallback : selected).isEmpty {
                        objectActionRequest = ObjectActionRequest(sources: selected.isEmpty ? fallback : selected)
                    } else {
                        actionPanelItem = item
                    }
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    guard press.modifiers.contains(.command),
                          let character = press.characters.first,
                          let index = commandShortcutIndex(for: character) else { return .ignored }
                    if unifiedResults.indices.contains(index) {
                        runSearchItem(unifiedResults[index])
                    } else if searchText.isEmpty, launcherRecentApps.indices.contains(index) {
                        appState.launch(launcherRecentApps[index])
                    } else {
                        return .ignored
                    }
                    return .handled
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search text")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSearchFieldFocused ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(isSearchFieldFocused ? 0.2 : 0.08), radius: isSearchFieldFocused ? 10 : 5, x: 0, y: 4)
    }

    private var searchStatusText: String {
        switch appState.intentSearchPhase {
        case .failed(let message): return message
        default: return searchSubtitle(for: unifiedResults.count)
        }
    }

    private var pendingPreviewBinding: Binding<ActionPreview?> {
        Binding(
            get: { appState.pendingActionPreview },
            set: { if $0 == nil { appState.cancelPendingAction() } }
        )
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.actionError != nil },
            set: { if !$0 { appState.dismissActionError() } }
        )
    }

    private var searchPlaceholder: String {
        if appState.isSemanticSearchAvailable {
            return "Search apps, files, projects, actions (use / for intent)"
        }
            return "Search apps, files, projects, actions, or recipes"
    }

    private var noResultsMessage: String {
        if appState.isSemanticSearchAvailable {
            return "Try searching by category, developer, or bundle identifier. Or start with '/' to use AI search."
        }
        return "Try searching by category, developer, or bundle identifier."
    }

    private func searchSubtitle(for count: Int) -> String {
        count == 1 ? "1 result" : "\(count) results"
    }

    private func launchTopResult() {
        // Return can arrive before the latest keystroke's ranking finishes.
        let pending = searchTask
        Task { @MainActor in
            await pending?.value
            guard let item = searchSelection.selectedItem(in: unifiedResults) else { return }
            runSearchItem(item)
        }
    }

    /// Typing never waits on ranking: each keystroke cancels the previous search, and only the
    /// newest one may publish its results.
    private func refreshSearchResults() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            let results = await makeUnifiedResults()
            guard !Task.isCancelled, results != unifiedResults else { return }
            unifiedResults = results
            searchSelection.reconcile(items: results)
            selectedObjectIDs.formIntersection(Set(results.map(\.id)))
        }
    }

    private func runSearchItem(_ item: SearchItem) {
        if case .recipe(let identifier) = item.target,
           let recipe = appState.recipeStore.recipes.first(where: { $0.id == identifier }),
           !recipe.variables.isEmpty {
            pendingRecipe = recipe
            return
        }
        appState.perform(item)
    }

    private func commandShortcutIndex(for character: Character) -> Int? {
        switch character {
        case "1"..."9": return character.wholeNumberValue.map { $0 - 1 }
        case "0": return 9
        default: return nil
        }
    }

    private func showLibrary() {
        withAnimation(.snappy(duration: 0.25)) {
            isLibraryExpanded = true
        }
    }

    private func captureInstantSend() {
        InstantSendService.capture { objects in
            if !objects.isEmpty {
                objectActionRequest = ObjectActionRequest(sources: objects)
            }
        }
    }

    private func beginCreatingFolder() {
        if preferences.sortOption != .custom {
            preferences.sortOption = .custom
        }
        newFolderName = ""
        isCreatingFolder = true
    }

    private func toggleObjectSelection(_ item: SearchItem) {
        guard LaunchObject(searchItem: item) != nil else { return }
        if selectedObjectIDs.contains(item.id) { selectedObjectIDs.remove(item.id) }
        else { selectedObjectIDs.insert(item.id) }
    }

    private func run(_ recipe: Recipe, values: [String: String]) {
        if recipe.workflow != nil {
            appState.runRecipe(recipe, values: values)
            return
        }
        guard case .resolved(let steps) = RecipeVariableResolver.resolve(
            steps: recipe.steps, variables: recipe.variables, values: values
        ) else { return }
        appState.requestAction(.runRecipe(identifier: recipe.id, name: recipe.name, steps: steps))
    }

    private var allApplicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.orderedCollections().isEmpty {
                Text("No applications were found on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ApplicationsGridView()
            }
        }
    }

    private func configure() {
        searchText = appState.searchQuery
        refreshSearchResults()
        WindowManager.shared.registerOpenWindowAction(openWindow)
        focusCancellable = appState.searchFocusPublisher
            .receive(on: RunLoop.main)
            .sink { _ in
                isSearchFieldFocused = true
            }

        if appState.totalAppCount == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.refreshApps()
            }
        }
    }
}

#Preview {
    let preferences = AppPreferences()
    let state = AppState(preferences: preferences)
    return ContentView()
        .environmentObject(state)
        .environmentObject(preferences)
}
