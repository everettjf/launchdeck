import Foundation

public struct SearchQuery: Equatable, Sendable {
    public enum Filter: Equatable, Sendable {
        case kinds(Set<SearchItemKind>)
        case path(String)
        case fileExtension(String)
        case title(String)
    }

    public let text: String
    public let filters: [Filter]

    public init(text: String, filters: [Filter] = []) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.filters = filters
    }

    public static func parse(_ rawValue: String) -> SearchQuery {
        var text: [String] = []
        var filters: [Filter] = []
        for token in tokenize(rawValue) {
            guard let separator = token.firstIndex(of: ":") else {
                text.append(token)
                continue
            }
            let key = token[..<separator].lowercased()
            let value = String(token[token.index(after: separator)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { text.append(token); continue }
            switch key {
            case "kind", "type":
                let kinds = Set(value.split(separator: ",").compactMap { kind(named: String($0)) })
                if kinds.isEmpty { text.append(token) } else { filters.append(.kinds(kinds)) }
            case "path", "in": filters.append(.path(value))
            case "ext": filters.append(.fileExtension(value.trimmingCharacters(in: CharacterSet(charactersIn: "."))))
            case "title", "name": filters.append(.title(value))
            case "app": filters.append(.kinds([.application])); text.append(value)
            default: text.append(token)
            }
        }
        return SearchQuery(text: text.joined(separator: " "), filters: filters)
    }

    public func matches(_ item: SearchItem) -> Bool {
        filters.allSatisfy { filter in
            switch filter {
            case .kinds(let kinds): kinds.contains(item.kind)
            case .path(let fragment):
                item.fileSystemPath?.localizedCaseInsensitiveContains(fragment) == true
            case .fileExtension(let value):
                item.fileSystemPath.map { URL(fileURLWithPath: $0).pathExtension.caseInsensitiveCompare(value) == .orderedSame } == true
            case .title(let value): item.title.localizedCaseInsensitiveContains(value)
            }
        }
    }

    public var displayDescription: String {
        filters.map {
            switch $0 {
            case .kinds(let kinds): "kind:\(kinds.map(\.rawValue).sorted().joined(separator: ","))"
            case .path(let value): "path:\(value)"
            case .fileExtension(let value): "ext:\(value)"
            case .title(let value): "title:\(value)"
            }
        }.joined(separator: " ")
    }

    private static func kind(named value: String) -> SearchItemKind? {
        let normalized = value.lowercased()
        if let exact = SearchItemKind.allCases.first(where: { $0.rawValue.lowercased() == normalized }) { return exact }
        switch normalized {
        case "app", "apps": return .application
        case "files": return .file
        case "folders", "directory", "directories": return .folder
        case "projects": return .project
        case "recipes", "workflow", "workflows": return .recipe
        case "clips", "clip": return .clipboard
        default: return nil
        }
    }

    private static func tokenize(_ value: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in value {
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
                else { current.append(character) }
            } else if character.isWhitespace, quote == nil {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

public extension SearchItem {
    var fileSystemPath: String? {
        switch target {
        case .application(_, let path), .file(let path), .folder(let path), .project(let path): path
        case .registeredAction, .systemSetting, .shortcut, .recipe, .copyText, .url, .systemCommand, .clipboardEntry: nil
        }
    }
}
