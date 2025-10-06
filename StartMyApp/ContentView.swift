import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText: String = ""
    @State private var focusCancellable: AnyCancellable?
    @State private var didAppear = false
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""

    private var searchResults: [DiscoveredApp] {
        // Use semantic results if they exist
        if !appState.semanticSearchResults.isEmpty {
            return appState.semanticSearchResults
        }
        // Otherwise use keyword results
        return appState.appsMatchingSearch()
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
        .sheet(item: $appState.presentedAppInfo, onDismiss: appState.dismissAppInfo) { info in
            AppInfoView(info: info)
                .environmentObject(appState)
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
                                            apps: recentApps) {
                                Button("Clear") {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        appState.clearRecents()
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .help("Clear recently launched apps")
                            }
                        }
                        allApplicationsSection
                    } else {
                        if appState.isSemanticSearching {
                            // Show loading indicator for semantic search
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                VStack(spacing: 8) {
                                    Text("Searching with AI...")
                                        .font(.title3.weight(.semibold))
                                    Text("Using Apple Foundation Models to find matching apps")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.top, 48)
                            .frame(maxWidth: .infinity)
                        } else if searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No results")
                                    .font(.title3.weight(.semibold))
                                Text(noResultsMessage)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 32)
                        } else {
                            AppGridSection(title: searchSectionTitle,
                                            apps: searchResults) {
                                Text(searchSubtitle(for: searchResults.count))
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

    private var searchPlaceholder: String {
        if appState.isSemanticSearchAvailable {
            return "Search apps (use / for AI search)"
        }
        return "Search apps, categories, or developers"
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
        guard let app = searchResults.first else { return }
        appState.launch(app)
    }

private func configure() {
    print("ContentView configure - total apps: \(appState.totalAppCount)")
    searchText = appState.searchQuery
    focusCancellable = appState.searchFocusPublisher
        .receive(on: RunLoop.main)
        .sink { _ in
            print("Search focus requested")
            isSearchFieldFocused = true
        }

    // If no apps loaded, trigger a refresh
    if appState.totalAppCount == 0 {
        print("No apps found, triggering refresh")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.refreshApps()
        }
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
