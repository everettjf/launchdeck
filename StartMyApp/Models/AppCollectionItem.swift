import Foundation

struct AppCollectionItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case app
        case folder
    }

    struct Folder: Codable, Equatable {
        var id: String
        var name: String
        var appIdentifiers: [String]
    }

    var id: String
    var kind: Kind
    var appIdentifier: String?
    var folder: Folder?

    static func app(_ identifier: String) -> AppCollectionItem {
        AppCollectionItem(id: identifier, kind: .app, appIdentifier: identifier, folder: nil)
    }

    static func folder(id: String = UUID().uuidString, name: String, appIdentifiers: [String]) -> AppCollectionItem {
        let folder = Folder(id: id, name: name, appIdentifiers: appIdentifiers)
        return AppCollectionItem(id: folder.id, kind: .folder, appIdentifier: nil, folder: folder)
    }

    var containedAppIdentifiers: [String] {
        switch kind {
        case .app:
            return appIdentifier.map { [$0] } ?? []
        case .folder:
            return folder?.appIdentifiers ?? []
        }
    }
}
