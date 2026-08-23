import Foundation
import LaunchDeckCore

enum SearchContextAction: String, Identifiable, CaseIterable, Sendable {
    case open
    case reveal
    case quickLook
    case copyPath
    case openTerminal
    case rename
    case move
    case duplicate
    case compress
    case tag
    case trash
    case paste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .reveal: "Reveal in Finder"
        case .quickLook: "Quick Look"
        case .copyPath: "Copy Path"
        case .openTerminal: "Open Terminal Here"
        case .rename: "Rename…"
        case .move: "Move…"
        case .duplicate: "Duplicate"
        case .compress: "Compress to ZIP"
        case .tag: "Set Finder Tags…"
        case .trash: "Move to Trash…"
        case .paste: "Paste into Frontmost App"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .quickLook: "eye"
        case .copyPath: "doc.on.doc"
        case .openTerminal: "terminal"
        case .rename: "pencil"
        case .move: "folder.badge.plus"
        case .duplicate: "plus.square.on.square"
        case .compress: "archivebox"
        case .tag: "tag"
        case .trash: "trash"
        case .paste: "text.insert"
        }
    }

    var keyboardHint: String? {
        switch self {
        case .open: "↩"
        case .reveal: "⌘↩"
        case .quickLook: "Space"
        case .copyPath: "⇧⌘C"
        case .openTerminal, .rename, .move, .duplicate, .compress, .tag, .trash: nil
        case .paste: "⇧↩"
        }
    }
}

enum SearchContextActionCatalog {
    static func actions(for item: SearchItem) -> [SearchContextAction] {
        switch item.kind {
        case .application:
            [.open, .reveal, .copyPath]
        case .file:
            [.open, .quickLook, .reveal, .copyPath, .rename, .move, .duplicate, .compress, .tag, .trash]
        case .folder, .project:
            [.open, .quickLook, .reveal, .copyPath, .openTerminal, .rename, .move, .duplicate, .compress, .tag, .trash]
        case .recipe, .shortcut, .setting:
            [.open]
        case .action:
            []
        case .calculation, .emoji:
            [.open]
        case .quicklink:
            [.open]
        case .clipboard:
            [.open, .paste]
        case .snippet, .windowAction:
            [.open]
        case .extensionCommand:
            [.open]
        }
    }
}
