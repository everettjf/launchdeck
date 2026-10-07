import AppKit
import Combine
import Foundation
import LaunchDeckCore
import SwiftUI

/// The app library: favorites, hidden apps, launching, recents, grid ordering and folders.
extension AppState {
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

    func updateRecents(with app: DiscoveredApp) {
        let updated = RecentLaunchList.recordingLaunch(of: app, in: recents, maxCount: recentsStore.maxCount)
        launchCountStore.recordLaunch(of: app.identifier)
        recents = updated
        recentsStore.save(updated)
    }

    func clearRecents() {
        recents = []
        recentsStore.save([])
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

    /// The grid reads this several times per render and AppState republishes changes from
    /// every sub-store, so the sorted result is reused until one of its inputs changes.
    func orderedCollections() -> [AppCollectionItem] {
        let key = CollectionOrderingKey(sortOption: preferences.sortOption, showHiddenApps: preferences.showHiddenApps,
                                        hiddenApps: preferences.hiddenApps, layout: layout, apps: apps,
                                        recents: recents,
                                        launchCounts: preferences.sortOption == .mostLaunched ? launchCountStore.counts : [:])
        if let cachedCollections, cachedCollections.key == key { return cachedCollections.value }
        let value = computeOrderedCollections()
        cachedCollections = (key, value)
        return value
    }

    private func computeOrderedCollections() -> [AppCollectionItem] {
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
            return AppSorting.mostLaunched(apps, launchCounts: launchCountStore.counts)
        case .recentlyLaunched:
            return AppSorting.recentlyLaunched(apps, recents: recents)
        }
    }
}
