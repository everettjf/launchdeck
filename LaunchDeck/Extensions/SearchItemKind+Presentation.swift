import LaunchDeckCore

extension SearchItemKind {
    var displayName: String {
        switch self {
        case .application: "App"
        case .file: "File"
        case .folder: "Folder"
        case .project: "Project"
        case .action: "Command"
        case .setting: "Setting"
        case .shortcut: "Shortcut"
        case .recipe: "Recipe"
        case .calculation: "Calculation"
        case .quicklink: "Quick Link"
        case .emoji: "Emoji"
        case .clipboard: "Clipboard"
        case .snippet: "Snippet"
        case .windowAction: "Window Command"
        case .extensionCommand: "Extension Command"
        }
    }

    var systemImage: String {
        switch self {
        case .application: "app"
        case .file: "doc"
        case .folder: "folder"
        case .project: "hammer"
        case .action: "bolt"
        case .setting: "gearshape"
        case .shortcut: "command"
        case .recipe: "list.bullet.rectangle"
        case .calculation: "function"
        case .quicklink: "link"
        case .emoji: "face.smiling"
        case .clipboard: "clipboard"
        case .snippet: "text.quote"
        case .windowAction: "macwindow"
        case .extensionCommand: "puzzlepiece.extension"
        }
    }
}
