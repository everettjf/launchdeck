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

    private var unifiedResults: [SearchItem] {
        let query = searchText.hasPrefix("/") ? String(searchText.dropFirst()) : searchText
        guard !query.isEmpty else { return [] }
        let local = appState.searchItems(matching: query).filter { selectedKinds.contains($0.kind) }
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

    private var allApps: [DiscoveredApp] {
        appState.allApps()
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
            mainContent
        }
        .onAppear(perform: configure)
        .onDisappear { focusCancellable?.cancel() }
        .onChange(of: searchText) { _, newValue in
            if appState.searchQuery != newValue {
                appState.searchQuery = newValue
                // Handle semantic search state based on input
                appState.handleSearchQueryChange(newValue)
            }
        }
        .onReceive(appState.$searchQuery.removeDuplicates()) { incoming in
            if searchText != incoming {
                searchText = incoming
            }
        }
        .onChange(of: unifiedResults.map(\.id), initial: true) {
            searchSelection.reconcile(items: unifiedResults)
            selectedObjectIDs.formIntersection(Set(unifiedResults.map(\.id)))
        }
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
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .opacity(0.25)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 36) {
                    if searchText.isEmpty {
                        if !favoriteApps.isEmpty {
                            AppGridSection(title: "Favorites",
                                            apps: favoriteApps)
                        }
                        if preferences.showRecentApps && !recentApps.isEmpty {
                            AppGridSection(title: "Recently Launched",
                                           apps: recentApps,
                                           trailing: {
                                Button("Clear") {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        appState.clearRecents()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Clear recently launched apps")
                            })
                        }
                        allApplicationsSection
                    } else {
                        if unifiedResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No results")
                                    .font(.title3.weight(.semibold))
                                Text(noResultsMessage)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 32)
                        } else {
                            SearchKindFilterBar(selectedKinds: $selectedKinds)
                            UnifiedSearchResultsView(items: unifiedResults,
                                                     selectedIdentifier: searchSelection.selectedIdentifier,
                                                     includedIdentifiers: selectedObjectIDs,
                                                     reason: appState.intentDetail,
                                                     onToggleIncluded: toggleObjectSelection,
                                                     onRun: runSearchItem) {
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
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
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

    private var header: some View {
        HStack(spacing: 12) {
            searchField
                .frame(maxWidth: 500)
            Spacer()

            if searchText.isEmpty {
                Text("All Applications")
                    .font(.title3.weight(.semibold))
                Text("\(appState.totalAppCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        appState.refreshApps()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Menu {
                        ForEach(AppPreferences.SortOption.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    preferences.sortOption = option
                                }
                            } label: {
                                if option == preferences.sortOption {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                        if preferences.sortOption != .custom {
                            Divider()
                            Button("Restore Default Order") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    preferences.sortOption = .custom
                                }
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    Divider()

                    Button {
                        if preferences.sortOption != .custom {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                preferences.sortOption = .custom
                            }
                        }
                        newFolderName = ""
                        isCreatingFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        openWindow(id: "recipe-studio")
                    } label: {
                        Label("New Recipe Studio", systemImage: "square.stack.3d.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)
            }

            Button {
                InstantSendService.capture { objects in
                    if !objects.isEmpty { objectActionRequest = ObjectActionRequest(sources: objects) }
                }
            } label: { Label("Instant Send", systemImage: "paperplane") }
            .help("Capture the Finder selection, current URL, selected text, or clipboard")

            if appState.canUndoObjectAction {
                Button {
                    appState.undoLastObjectAction()
                } label: { Label("Undo \(appState.objectUndoActionName)", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
            }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.ultraThickMaterial)
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
        guard let item = searchSelection.selectedItem(in: unifiedResults) else { return }
        runSearchItem(item)
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

    private func toggleObjectSelection(_ item: SearchItem) {
        guard LaunchObject(searchItem: item) != nil else { return }
        if selectedObjectIDs.contains(item.id) { selectedObjectIDs.remove(item.id) }
        else { selectedObjectIDs.insert(item.id) }
    }

    private func run(_ recipe: Recipe, values: [String: String]) {
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

private struct UnifiedSearchResultsView<Trailing: View>: View {
    let items: [SearchItem]
    let selectedIdentifier: String?
    let includedIdentifiers: Set<String>
    let reason: (SearchItem) -> String?
    let onToggleIncluded: (SearchItem) -> Void
    let onRun: (SearchItem) -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Search").font(.title2.weight(.semibold)); Spacer(); trailing() }
            LazyVStack(spacing: 6) {
                ForEach(items) { item in
                    SearchResultRow(item: item,
                                    isSelected: item.id == selectedIdentifier,
                                    isIncluded: includedIdentifiers.contains(item.id),
                                    detail: reason(item) ?? item.subtitle ?? item.kind.rawValue.capitalized) {
                        onToggleIncluded(item)
                    } onRun: {
                        onRun(item)
                    }
                }
            }
        }
    }

}

private struct SearchKindFilterBar: View {
    @Binding var selectedKinds: Set<SearchItemKind>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("All") { selectedKinds = Set(SearchItemKind.allCases) }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedKinds.count == SearchItemKind.allCases.count ? .accentColor : .secondary)
                ForEach(SearchItemKind.allCases, id: \.self) { kind in
                    Button(kind.rawValue.capitalized) { toggle(kind) }
                        .buttonStyle(.bordered)
                        .tint(selectedKinds.contains(kind) ? .accentColor : .secondary)
                        .accessibilityValue(selectedKinds.contains(kind) ? "Included" : "Excluded")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search categories")
    }

    private func toggle(_ kind: SearchItemKind) {
        if selectedKinds == Set(SearchItemKind.allCases) {
            selectedKinds = [kind]
        } else if selectedKinds.contains(kind) {
            selectedKinds.remove(kind)
            if selectedKinds.isEmpty { selectedKinds = Set(SearchItemKind.allCases) }
        } else {
            selectedKinds.insert(kind)
        }
    }
}

private struct SearchActionPanel: View {
    @Environment(\.dismiss) private var dismiss
    let item: SearchItem
    let actions: [SearchContextAction]
    let onRun: (SearchContextAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title).font(.title2.weight(.semibold))
            Text(item.subtitle ?? item.kind.rawValue.capitalized).foregroundStyle(.secondary)
            if actions.isEmpty {
                ContentUnavailableView("No Available Actions", systemImage: "bolt.slash")
            } else {
                List(actions) { action in
                    Button { onRun(action) } label: {
                        HStack {
                            Label(action.title, systemImage: action.systemImage)
                            Spacer()
                            if let hint = action.keyboardHint {
                                Text(hint).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack { Spacer(); Button("Cancel", role: .cancel) { dismiss() } }
        }
        .padding(24)
        .frame(width: 440, height: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(item.title)")
    }
}

private struct ActionPreviewView: View {
    let preview: ActionPreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Action Preview", systemImage: preview.risk == .elevated ? "exclamationmark.shield" : "checkmark.shield")
                .font(.title2.weight(.semibold))
            Text(preview.title).font(.headline)
            Text(preview.summary).foregroundStyle(.secondary)
            LabeledContent("Target", value: preview.target)
            if !preview.steps.isEmpty {
                GroupBox("Steps") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(preview.steps.enumerated()), id: \.element.id) { index, step in
                            Text("\(index + 1). \(step.title)").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 4)
                }
            }
            ForEach(preview.permissions, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            HStack { Spacer(); Button("Cancel", role: .cancel, action: onCancel); Button("Run", action: onConfirm).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520)
    }
}

private struct NewFolderSheet: View {
    @Binding var isPresented: Bool
    @Binding var folderName: String
    var onCreate: (String) -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Folder")
                .font(.title2.weight(.semibold))

            TextField("Folder Name", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit(commit)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Create") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear {
            if folderName.isEmpty {
                folderName = defaultFolderName
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    private func commit() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        folderName = ""
        isPresented = false
    }

    private var defaultFolderName: String {
        "New Folder"
    }
}

#Preview {
    let preferences = AppPreferences()
    let state = AppState(preferences: preferences)
    return ContentView()
        .environmentObject(state)
        .environmentObject(preferences)
}
