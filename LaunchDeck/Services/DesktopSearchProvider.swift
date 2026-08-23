import Foundation
import LaunchDeckCore

enum DesktopSearchProvider {
    static func items(matching rawQuery: String,
                      clipboardEnabled: Bool,
                      clipboardEntries: [ClipboardEntry],
                      snippets: [Snippet]) -> [SearchItem] {
        let query = rawQuery.lowercased()
        var items: [SearchItem] = []

        if clipboardEnabled {
            items += clipboardEntries
                .filter { $0.text.lowercased().contains(query) || $0.typeName.lowercased().contains(query) }
                .prefix(20)
                .map {
                    SearchItem(id: "clipboard:\($0.id)", kind: .clipboard,
                               title: String($0.text.prefix(80)), subtitle: "\($0.typeName) · \($0.copiedAt.formatted())",
                               keywords: ["clipboard", "copy", "paste", $0.typeName], target: .clipboardEntry(identifier: $0.id))
                }
        }

        items += snippets.filter {
            $0.name.lowercased().contains(query)
                || $0.keyword.lowercased().contains(query)
                || $0.content.lowercased().contains(query)
        }.map {
            SearchItem(id: "snippet:\($0.id)", kind: .snippet, title: $0.name, subtitle: $0.keyword,
                       keywords: ["snippet", "text", $0.keyword],
                       target: .copyText($0.expanded(clipboard: clipboardEntries.first?.text)))
        }

        items += DesktopWindowCommand.allCases.filter {
            $0.title.lowercased().contains(query) || $0.rawValue.lowercased().contains(query)
        }.map {
            SearchItem(id: $0.rawValue, kind: .windowAction, title: $0.title,
                       keywords: ["window", "move", "resize"], target: .systemCommand($0.rawValue))
        }
        return items
    }
}
