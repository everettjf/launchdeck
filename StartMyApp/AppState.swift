import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var apps: [DiscoveredApp] = []
    @Published var searchQuery: String = ""
    @Published private(set) var favorites: Set<String>
    @Published private(set) var recents: [RecentLaunch]

    private let favoritesStore: FavoritesStore
    private let recentsStore: RecentsStore
    private let discoveryService: ApplicationDiscoveryService
    private let preferences: AppPreferences
    private let focusPublisher = PassthroughSubject<Void, Never>()

    var searchFocusPublisher: AnyPublisher<Void, Never> {
        focusPublisher.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()

    init(preferences: AppPreferences,
         favoritesStore: FavoritesStore = FavoritesStore(),
         recentsStore: RecentsStore = RecentsStore(maxCount: 12),
         discoveryService: ApplicationDiscoveryService = ApplicationDiscoveryService()) {
        self.preferences = preferences
        self.favoritesStore = favoritesStore
        self.recentsStore = recentsStore
        self.discoveryService = discoveryService
        self.favorites = favoritesStore.load()
        self.recents = recentsStore.load()

        setupBindings()
        refreshApps()
    }

    private func setupBindings() {
        preferences.$showSystemApps
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshApps()
            }
            .store(in: &cancellables)
    }

    func refreshApps() {
        let includeSystemApps = preferences.showSystemApps
        let discoveryService = discoveryService
        Task.detached(priority: .userInitiated) { [weak self] in
            let discovered = discoveryService.discoverApplications(includeSystemApps: includeSystemApps)
            await MainActor.run {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.apps = discovered
                }
            }
        }
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
        var updated = recents

        if let index = updated.firstIndex(where: { $0.identifier == app.identifier }) {
            var launch = updated.remove(at: index)
            launch.lastLaunch = Date()
            launch.launchCount += 1
            updated.insert(launch, at: 0)
        } else {
            let launch = RecentLaunch(identifier: app.identifier,
                                      displayName: app.name,
                                      path: app.path,
                                      lastLaunch: Date(),
                                      launchCount: 1)
            updated.insert(launch, at: 0)
        }

        if updated.count > recentsStore.maxCount {
            updated = Array(updated.prefix(recentsStore.maxCount))
        }

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

    func appsMatchingSearch() -> [DiscoveredApp] {
        guard !searchQuery.isEmpty else { return visibleAppsSorted() }
        let term = searchQuery.lowercased()
        return visibleAppsSorted().filter { app in
            app.searchableText.contains(term)
        }
    }

    func favoriteApps() -> [DiscoveredApp] {
        visibleAppsSorted().filter { favorites.contains($0.identifier) }
    }

    func recentApps() -> [DiscoveredApp] {
        let lookup = Dictionary(uniqueKeysWithValues: visibleAppsSorted().map { ($0.identifier, $0) })
        return recents.compactMap { launch in
            guard let app = lookup[launch.identifier] else { return nil }
            return app
        }
    }

    func allApps() -> [DiscoveredApp] {
        visibleAppsSorted()
    }

    private func visibleAppsSorted() -> [DiscoveredApp] {
        apps.sorted { first, second in
            let firstWeight = sortWeight(for: first)
            let secondWeight = sortWeight(for: second)
            if firstWeight == secondWeight {
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
            return firstWeight > secondWeight
        }
    }

    private func sortWeight(for app: DiscoveredApp) -> Int {
        var weight = 0
        if favorites.contains(app.identifier) {
            weight += 10
        }
        if recents.first?.identifier == app.identifier {
            weight += 5
        }
        if app.isSystemApp {
            weight -= 1
        }
        return weight
    }
}
