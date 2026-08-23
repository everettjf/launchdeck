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

    private var searchResults: [DiscoveredApp] {
        let local = appState.appsMatchingSearch()
        guard searchText.hasPrefix("/"), !appState.semanticSearchResults.isEmpty else {
            return local
        }
        let semanticIDs = Set(appState.semanticSearchResults.map(\.identifier))
        return appState.semanticSearchResults + local.filter { !semanticIDs.contains($0.identifier) }
    }

    private var unifiedResults: [SearchItem] {
        let query = searchText.hasPrefix("/") ? String(searchText.dropFirst()) : searchText
        let local = appState.searchItems(matching: query)
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
        .animation(.spring(response: 0.65, dampingFraction: 0.82), value: didAppear)
        .sheet(item: pendingPreviewBinding) { preview in
            ActionPreviewView(preview: preview,
                              onCancel: appState.cancelPendingAction,
                              onConfirm: appState.confirmPendingAction)
        }
        .alert("Action Failed", isPresented: actionErrorBinding) {
            Button("OK") { appState.dismissActionError() }
        } message: {
            Text(appState.actionError ?? "")
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
                                .foregroundColor(.secondary)
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
                            UnifiedSearchResultsView(items: unifiedResults,
                                                     reason: appState.intentDetail,
                                                     onRun: appState.perform) {
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.bordered)
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
            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($isSearchFieldFocused)
                .onSubmit(launchTopResult)
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

    private var searchSectionTitle: String {
        if !appState.semanticSearchResults.isEmpty {
            return "AI Search Results"
        }
        return "Search"
    }

    private var searchStatusText: String {
        switch appState.intentSearchPhase {
        case .failed(let message): return message
        default: return searchSubtitle(for: searchResults.count)
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
        guard let item = unifiedResults.first else { return }
        appState.perform(item)
    }

private func configure() {
    searchText = appState.searchQuery
    WindowManager.shared.registerOpenWindowAction(openWindow)
    focusCancellable = appState.searchFocusPublisher
        .receive(on: RunLoop.main)
        .sink { _ in
            isSearchFieldFocused = true
        }

    // If no apps loaded, trigger a refresh
    if appState.totalAppCount == 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.refreshApps()
        }
    }
}

private struct UnifiedSearchResultsView<Trailing: View>: View {
    let items: [SearchItem]
    let reason: (SearchItem) -> String?
    let onRun: (SearchItem) -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Search").font(.title2.weight(.semibold)); Spacer(); trailing() }
            LazyVStack(spacing: 6) {
                ForEach(items) { item in
                    Button { onRun(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(item.kind)).frame(width: 24).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                                Text(reason(item) ?? item.subtitle ?? item.kind.rawValue.capitalized)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Text(item.kind.rawValue.capitalized).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func icon(_ kind: SearchItemKind) -> String {
        switch kind {
        case .application: "app"
        case .file: "doc"
        case .folder: "folder"
        case .project: "hammer"
        case .action: "bolt"
        case .setting: "gearshape"
        case .shortcut: "command"
        case .recipe: "list.bullet.rectangle"
        }
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
