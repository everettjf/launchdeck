import Combine
import Foundation
import LaunchDeckCore

/// Orchestrates AI semantic search (the `/` query prefix): debounce, cancellation,
/// and result state. The actual model calls live in SemanticSearchService.
@MainActor
final class SemanticSearchController: ObservableObject {
    @Published private(set) var results: [DiscoveredApp] = []
    @Published private(set) var isSearching: Bool = false
    private(set) var isAvailable: Bool = false

    /// Supplies the current app catalog when a debounced search fires.
    var appsProvider: () -> [DiscoveredApp] = { [] }

    private var service: SemanticSearchService?
    private var searchTask: Task<Void, Never>?
    private var debounceTimer: Timer?
    private var currentRawQuery: String = ""

    func initialize() {
        Task {
            let service = await SemanticSearchService()
            self.service = service
            self.isAvailable = true
            objectWillChange.send()
        }
    }

    /// Called when the search query changes.
    func handleQueryChange(_ query: String) {
        currentRawQuery = query

        // Cancel any pending debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // 1. If search is empty, clear AI results
        guard !query.isEmpty else {
            clear()
            return
        }

        // 2. Check if using AI search (starts with /)
        let useAISearch = query.hasPrefix("/")
        let actualQuery = useAISearch ? String(query.dropFirst()) : query

        // 3. If not using AI search, clear AI results
        if !useAISearch {
            clear()
            return
        }

        // 4. If only "/" is entered (no actual query), clear AI results
        if actualQuery.isEmpty {
            clear()
            return
        }

        // 5. If using AI search (/xxx), trigger semantic search with debounce
        if isAvailable, !actualQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            // Debounce: wait 2 seconds before triggering AI search
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.trigger(query: actualQuery)
                }
            }
        }
    }

    private func clear() {
        // Cancel any debounce timer
        debounceTimer?.invalidate()
        debounceTimer = nil

        // Cancel any ongoing search task
        searchTask?.cancel()

        // Clear the searching state
        isSearching = false

        // Clear results
        if !results.isEmpty {
            results = []
        }
    }

    private func trigger(query: String) {
        // Cancel any ongoing search
        searchTask?.cancel()

        isSearching = true

        searchTask = Task { @MainActor in
            guard let service else {
                isSearching = false
                return
            }

            let results = await service.searchApps(appsProvider(), query: query)

            // Check if search query hasn't changed
            let currentQuery = currentRawQuery.hasPrefix("/")
                ? String(currentRawQuery.dropFirst())
                : currentRawQuery

            if currentQuery == query && !Task.isCancelled {
                self.results = results.map { $0.app }
            }

            isSearching = false
        }
    }
}
