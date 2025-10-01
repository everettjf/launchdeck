import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct ApplicationsGridView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    @State private var draggingItemID: String?
    @State private var folderCreationTargetID: String?
    @State private var folderAppendTargetID: String?
    @State private var itemSizes: [String: CGSize] = [:]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: preferences.gridScale.minimumTileWidth,
                             maximum: preferences.gridScale.maximumTileWidth),
                  spacing: preferences.gridScale.horizontalSpacing,
                  alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns,
                  alignment: .leading,
                  spacing: preferences.gridScale.verticalSpacing) {
            ForEach(appState.orderedCollections(), id: \.id) { item in
                content(for: item)
                    .onDrag {
                        draggingItemID = item.id
                        folderCreationTargetID = nil
                        folderAppendTargetID = nil
                        return NSItemProvider(object: item.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: ApplicationsDropDelegate(item: item,
                                                                             tileSize: itemSizes[item.id] ?? .init(width: preferences.gridScale.minimumTileWidth + 8, height: preferences.gridScale.minimumTileWidth + 32),
                                                                             draggingItemID: $draggingItemID,
                                                                             folderCreationTargetID: $folderCreationTargetID,
                                                                             folderAppendTargetID: $folderAppendTargetID,
                                                                             appState: appState))
            }
        }
        .onDrop(of: [.text], delegate: ApplicationsDropDelegate(item: nil,
                                                                tileSize: .zero,
                                                                draggingItemID: $draggingItemID,
                                                                folderCreationTargetID: $folderCreationTargetID,
                                                                folderAppendTargetID: $folderAppendTargetID,
                                                                appState: appState))
    }

    @ViewBuilder
    private func content(for item: AppCollectionItem) -> some View {
        switch item.kind {
        case .app:
            if let identifier = item.appIdentifier, let app = appState.app(for: identifier) {
                AppTile(app: app,
                        isDropTarget: folderCreationTargetID == item.id,
                        onSizeChange: { size in itemSizes[item.id] = size })
            }
        case .folder:
            if let folder = item.folder {
                FolderTile(itemID: item.id,
                           folder: folder,
                           isDropTarget: folderAppendTargetID == item.id,
                           onSizeChange: { size in itemSizes[item.id] = size })
            }
        }
    }
}

private struct ApplicationsDropDelegate: DropDelegate {
    let item: AppCollectionItem?
    let tileSize: CGSize
    @Binding var draggingItemID: String?
    @Binding var folderCreationTargetID: String?
    @Binding var folderAppendTargetID: String?
    let appState: AppState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingItemID else { return }
        guard let item else {
            appState.moveItem(draggingID, before: nil)
            return
        }
        guard item.id != draggingID else { return }
        appState.moveItem(draggingID, before: item.id)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        folderCreationTargetID = nil
        folderAppendTargetID = nil
        guard let item else {
            return DropProposal(operation: .move)
        }
        guard let draggingID = draggingItemID else { return DropProposal(operation: .move) }
        guard let draggingItem = appState.collection(withID: draggingID) else { return DropProposal(operation: .move) }

        switch item.kind {
        case .folder:
            guard draggingItem.kind == .app else { return DropProposal(operation: .move) }
            folderAppendTargetID = item.id
        case .app:
            guard draggingItem.kind == .app else { return DropProposal(operation: .move) }
            if isInsideFolderHotZone(info.location) {
                folderCreationTargetID = item.id
            }
        }

        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if folderCreationTargetID == item?.id {
            folderCreationTargetID = nil
        }
        if folderAppendTargetID == item?.id {
            folderAppendTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingItemID = nil
            folderCreationTargetID = nil
            folderAppendTargetID = nil
        }
        guard let draggingID = draggingItemID else { return false }

        if let folderID = folderAppendTargetID {
            appState.addApp(draggingID, toFolder: folderID)
            return true
        }

        if let targetID = folderCreationTargetID {
            appState.createFolder(byCombining: targetID, and: draggingID)
            return true
        }

        return true
    }

    private func isInsideFolderHotZone(_ location: CGPoint) -> Bool {
        guard tileSize != .zero else { return false }
        let center = CGPoint(x: tileSize.width / 2, y: tileSize.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let threshold = min(tileSize.width, tileSize.height) * 0.35
        return distance < threshold
    }
}
