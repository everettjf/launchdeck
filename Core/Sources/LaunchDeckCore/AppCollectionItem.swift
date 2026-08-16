import Foundation

public struct AppCollectionItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case app
        case folder
    }

    public struct Folder: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var appIdentifiers: [String]

        public init(id: String, name: String, appIdentifiers: [String]) {
            self.id = id
            self.name = name
            self.appIdentifiers = appIdentifiers
        }
    }

    public var id: String
    public var kind: Kind
    public var appIdentifier: String?
    public var folder: Folder?

    public init(id: String, kind: Kind, appIdentifier: String?, folder: Folder?) {
        self.id = id
        self.kind = kind
        self.appIdentifier = appIdentifier
        self.folder = folder
    }

    public static func app(_ identifier: String) -> AppCollectionItem {
        AppCollectionItem(id: identifier, kind: .app, appIdentifier: identifier, folder: nil)
    }

    public static func folder(id: String = UUID().uuidString, name: String, appIdentifiers: [String]) -> AppCollectionItem {
        let folder = Folder(id: id, name: name, appIdentifiers: appIdentifiers)
        return AppCollectionItem(id: folder.id, kind: .folder, appIdentifier: nil, folder: folder)
    }

    public var containedAppIdentifiers: [String] {
        switch kind {
        case .app:
            return appIdentifier.map { [$0] } ?? []
        case .folder:
            return folder?.appIdentifiers ?? []
        }
    }
}
