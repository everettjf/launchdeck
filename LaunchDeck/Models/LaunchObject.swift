import Foundation
import LaunchDeckCore

nonisolated struct LaunchObject: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case application, file, folder, url, text, clipboard }

    let id: String
    let kind: Kind
    let title: String
    let value: String
    let applicationIdentifier: String?

    init(id: String? = nil, kind: Kind, title: String, value: String, applicationIdentifier: String? = nil) {
        self.id = id ?? "\(kind.rawValue):\(value)"
        self.kind = kind
        self.title = title
        self.value = value
        self.applicationIdentifier = applicationIdentifier
    }

    init?(searchItem: SearchItem) {
        switch searchItem.target {
        case .application(let identifier, let path):
            self.init(id: searchItem.id, kind: .application, title: searchItem.title, value: path,
                      applicationIdentifier: identifier)
        case .file(let path): self.init(id: searchItem.id, kind: .file, title: searchItem.title, value: path)
        case .folder(let path), .project(let path): self.init(id: searchItem.id, kind: .folder, title: searchItem.title, value: path)
        case .url(let url): self.init(id: searchItem.id, kind: .url, title: searchItem.title, value: url.absoluteString)
        case .copyText(let text): self.init(id: searchItem.id, kind: .text, title: searchItem.title, value: text)
        case .clipboardEntry(let identifier):
            self.init(id: searchItem.id, kind: .clipboard, title: searchItem.title, value: identifier.uuidString)
        case .registeredAction, .systemSetting, .shortcut, .recipe, .systemCommand: return nil
        }
    }

    var fileURL: URL? {
        switch kind {
        case .application, .file, .folder: URL(fileURLWithPath: value)
        case .url, .text, .clipboard: nil
        }
    }
}
