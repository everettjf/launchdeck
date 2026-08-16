import Foundation

/// Reconciles the persisted layout with the apps currently discovered on disk.
public enum LayoutSynchronizer {
    /// Returns a layout where uninstalled apps are dropped, folders follow the
    /// dissolution rule, and newly discovered apps are appended sorted by name.
    public static func sync(layout: [AppCollectionItem], with apps: [DiscoveredApp]) -> [AppCollectionItem] {
        let knownIdentifiers = Set(apps.map { $0.identifier })
        var updatedLayout: [AppCollectionItem] = []

        for item in layout {
            switch item.kind {
            case .app:
                guard let identifier = item.appIdentifier, knownIdentifiers.contains(identifier) else { continue }
                updatedLayout.append(.app(identifier))
            case .folder:
                guard var folder = item.folder else { continue }
                folder.appIdentifiers = folder.appIdentifiers.filter { knownIdentifiers.contains($0) }
                if let dissolved = FolderDissolution.item(for: folder, reusing: item) {
                    updatedLayout.append(dissolved)
                }
            }
        }

        let existingIdentifiers = Set(updatedLayout.flatMap { $0.containedAppIdentifiers })
        let appsByIdentifier = Dictionary(uniqueKeysWithValues: apps.map { ($0.identifier, $0) })
        let sortedMissing = knownIdentifiers
            .subtracting(existingIdentifiers)
            .compactMap { appsByIdentifier[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for app in sortedMissing {
            updatedLayout.append(.app(app.identifier))
        }

        return updatedLayout
    }
}

/// Rule applied whenever a folder's contents change:
/// 2+ apps keep the folder, exactly 1 app promotes it to a plain app item, 0 removes it.
public enum FolderDissolution {
    public static func item(for folder: AppCollectionItem.Folder, reusing item: AppCollectionItem) -> AppCollectionItem? {
        if folder.appIdentifiers.count >= 2 {
            var folderItem = item
            folderItem.folder = folder
            return folderItem
        } else if let singleIdentifier = folder.appIdentifiers.first {
            return .app(singleIdentifier)
        }
        return nil
    }
}

/// Suggests a folder name from the most common category among its apps.
public enum FolderNaming {
    public static func suggestedName(forAppIdentifiers identifiers: [String],
                                     appsByIdentifier: [String: DiscoveredApp]) -> String? {
        let categories = identifiers.compactMap { appsByIdentifier[$0]?.category }
        return categories.mostCommonElement()
    }
}

private extension Array where Element == String {
    func mostCommonElement() -> String? {
        guard !isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for element in self {
            counts[element, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }
}
