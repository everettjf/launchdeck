import Combine
import Foundation
import LaunchDeckCore

/// Owns the grid layout: ordering, folders, and persistence.
/// Pure merge/dissolution rules live in LaunchDeckCore (LayoutSynchronizer, FolderDissolution).
@MainActor
final class LayoutController: ObservableObject {
    @Published private(set) var layout: [AppCollectionItem]

    private let layoutStore: LayoutStore

    init(layoutStore: LayoutStore) {
        self.layoutStore = layoutStore
        self.layout = layoutStore.load()
    }

    var orderedIdentifiers: [String] {
        layout.flatMap { $0.containedAppIdentifiers }
    }

    func collection(withID id: String) -> AppCollectionItem? {
        layout.first { $0.id == id }
    }

    /// Reconciles the layout with the currently discovered apps (drops uninstalled
    /// apps, dissolves folders, appends new apps sorted by name).
    func sync(with apps: [DiscoveredApp]) {
        let updated = LayoutSynchronizer.sync(layout: layout, with: apps)
        layout = updated
        layoutStore.save(updated)
    }

    func createEmptyFolder(named name: String) {
        modifyLayout { layout in
            let folder = AppCollectionItem.folder(name: name, appIdentifiers: [])
            layout.append(folder)
        }
    }

    func renameFolder(id: String, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == id }),
                  layout[index].kind == .folder else { return }
            layout[index].folder?.name = newName
        }
    }

    func moveItem(_ draggedID: String, before targetID: String?) {
        guard draggedID != targetID else { return }
        modifyLayout { layout in
            guard let fromIndex = layout.firstIndex(where: { $0.id == draggedID }) else { return }
            let item = layout.remove(at: fromIndex)
            if let targetID, let targetIndex = layout.firstIndex(where: { $0.id == targetID }) {
                layout.insert(item, at: targetIndex)
            } else {
                layout.append(item)
            }
        }
    }

    func addApp(_ appID: String, toFolder folderID: String) {
        modifyLayout { layout in
            guard layout.contains(where: { $0.id == folderID }) else { return }
            if let appIndex = layout.firstIndex(where: { $0.id == appID }) {
                layout.remove(at: appIndex)
            }
            guard let folderIndex = layout.firstIndex(where: { $0.id == folderID }),
                  var folder = layout[folderIndex].folder else { return }
            guard !folder.appIdentifiers.contains(appID) else { return }
            folder.appIdentifiers.append(appID)
            layout[folderIndex].folder = folder
        }
    }

    func createFolder(byCombining firstID: String, and secondID: String, named folderName: String) {
        guard firstID != secondID else { return }
        modifyLayout { layout in
            guard let firstIndex = layout.firstIndex(where: { $0.id == firstID }),
                  let secondIndex = layout.firstIndex(where: { $0.id == secondID }) else { return }
            let firstItem = layout[firstIndex]
            let secondItem = layout[secondIndex]
            guard let firstApp = firstItem.appIdentifier,
                  let secondApp = secondItem.appIdentifier else { return }

            let lowerIndex = min(firstIndex, secondIndex)
            let higherIndex = max(firstIndex, secondIndex)
            layout.remove(at: higherIndex)
            layout.remove(at: lowerIndex)

            let folder = AppCollectionItem.folder(name: folderName, appIdentifiers: [firstApp, secondApp])
            layout.insert(folder, at: lowerIndex)
        }
    }

    func removeApp(_ appID: String, fromFolder folderID: String) {
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == folderID }),
                  var folder = layout[index].folder else { return }
            folder.appIdentifiers.removeAll { $0 == appID }
            if let dissolved = FolderDissolution.item(for: folder, reusing: layout[index]) {
                layout[index] = dissolved
            } else {
                layout.remove(at: index)
            }
        }
    }

    func deleteFolder(_ folderID: String) {
        modifyLayout { layout in
            guard let index = layout.firstIndex(where: { $0.id == folderID }),
                  let folder = layout[index].folder else { return }
            layout.remove(at: index)
            let insertIndex = min(index, layout.count)
            for (offset, identifier) in folder.appIdentifiers.enumerated() {
                layout.insert(.app(identifier), at: insertIndex + offset)
            }
        }
    }

    private func modifyLayout(_ modify: (inout [AppCollectionItem]) -> Void) {
        var updated = layout
        modify(&updated)
        layout = updated
        layoutStore.save(updated)
    }
}
