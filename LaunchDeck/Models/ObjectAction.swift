import Foundation

nonisolated enum ObjectAction: String, CaseIterable, Identifiable, Sendable {
    case open, reveal, copy, paste, openWith, move, duplicate, compress, trash, saveAsRecipe
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open"
        case .reveal: "Reveal in Finder"
        case .copy: "Copy"
        case .paste: "Paste into Source App"
        case .openWith: "Open With…"
        case .move: "Move To…"
        case .duplicate: "Duplicate"
        case .compress: "Compress"
        case .trash: "Move to Trash"
        case .saveAsRecipe: "Save Chain as Recipe"
        }
    }
    var systemImage: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .copy: "doc.on.doc"
        case .paste: "text.insert"
        case .openWith: "square.and.arrow.up"
        case .move: "folder.badge.plus"
        case .duplicate: "plus.square.on.square"
        case .compress: "archivebox"
        case .trash: "trash"
        case .saveAsRecipe: "list.bullet.rectangle"
        }
    }
    var requiresTarget: Bool { self == .move || self == .openWith }
    var isDestructive: Bool { self == .trash }
}

nonisolated enum ObjectActionCatalog {
    static func actions(for sources: [LaunchObject]) -> [ObjectAction] {
        guard !sources.isEmpty else { return [] }
        let areFiles = sources.allSatisfy { [.file, .folder].contains($0.kind) }
        let areOpenable = sources.allSatisfy { [.application, .file, .folder, .url].contains($0.kind) }
        let areRevealable = sources.allSatisfy { [.application, .file, .folder].contains($0.kind) }
        let arePasteable = sources.allSatisfy { [.text, .url, .file, .folder, .clipboard].contains($0.kind) }
        var result: [ObjectAction] = []
        if areOpenable { result.append(.open) }
        if areRevealable { result.append(.reveal) }
        result.append(.copy)
        if arePasteable { result.append(.paste) }
        if areFiles { result += [.openWith, .move, .duplicate, .compress, .trash] }
        return result
    }
}

nonisolated struct ObjectActionRequest: Identifiable, Hashable, Sendable {
    let id = UUID()
    var sources: [LaunchObject]
}
