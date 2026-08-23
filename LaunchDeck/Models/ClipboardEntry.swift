import Foundation

nonisolated struct ClipboardEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let copiedAt: Date

    init(id: UUID = UUID(), text: String, copiedAt: Date = .now) {
        self.id = id
        self.text = String(text.prefix(20_000))
        self.copiedAt = copiedAt
    }
}

nonisolated struct Snippet: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var keyword: String
    var content: String

    init(id: UUID = UUID(), name: String, keyword: String, content: String) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.content = content
    }

    func expanded(clipboard: String?, now: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        let date = formatter.string(from: now).split(separator: "T").first.map(String.init) ?? ""
        let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        return content.replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{time}", with: time)
    }
}
