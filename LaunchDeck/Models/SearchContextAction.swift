import Foundation
import LaunchDeckCore

enum SearchContextAction: String, Identifiable, CaseIterable, Sendable {
    case open
    case reveal
    case quickLook
    case copyPath
    case openTerminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .reveal: "Reveal in Finder"
        case .quickLook: "Quick Look"
        case .copyPath: "Copy Path"
        case .openTerminal: "Open Terminal Here"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .quickLook: "eye"
        case .copyPath: "doc.on.doc"
        case .openTerminal: "terminal"
        }
    }

    var keyboardHint: String? {
        switch self {
        case .open: "↩"
        case .reveal: "⌘↩"
        case .quickLook: "Space"
        case .copyPath: "⇧⌘C"
        case .openTerminal: nil
        }
    }
}

enum SearchContextActionCatalog {
    static func actions(for item: SearchItem) -> [SearchContextAction] {
        switch item.kind {
        case .application:
            [.open, .reveal, .copyPath]
        case .file:
            [.open, .quickLook, .reveal, .copyPath]
        case .folder, .project:
            [.open, .quickLook, .reveal, .copyPath, .openTerminal]
        case .recipe, .shortcut, .setting:
            [.open]
        case .action:
            []
        case .calculation, .emoji:
            [.open]
        case .quicklink:
            [.open]
        case .clipboard, .snippet, .windowAction:
            [.open]
        case .extensionCommand:
            [.open]
        }
    }
}
