import Foundation

nonisolated struct Quicklink: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var keyword: String
    var urlTemplate: String

    init(id: UUID = UUID(), name: String, keyword: String, urlTemplate: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.urlTemplate = urlTemplate
    }

    func url(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let value = urlTemplate.replacingOccurrences(of: "{query}", with: encoded)
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

nonisolated enum QuicklinkValidation {
    static func error(for quicklink: Quicklink) -> String? {
        let keyword = quicklink.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quicklink.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Quicklink name is required." }
        guard !keyword.isEmpty, !keyword.contains(where: { $0.isWhitespace }) else { return "Keyword must be one word." }
        guard quicklink.urlTemplate.contains("{query}") else { return "URL template must contain {query}." }
        guard let testURL = quicklink.url(for: "test"), ["https", "http"].contains(testURL.scheme?.lowercased() ?? "") else {
            return "Quicklinks support only HTTP and HTTPS URLs."
        }
        return nil
    }
}
