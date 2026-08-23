import Foundation

nonisolated struct ClipboardEntry: Codable, Hashable, Identifiable, Sendable {
    enum Content: Codable, Hashable, Sendable { case text(String), image(Data), files([String]) }
    let id: UUID
    let content: Content
    let copiedAt: Date
    let sourceBundleIdentifier: String?

    init(id: UUID = UUID(), content: Content, copiedAt: Date = .now, sourceBundleIdentifier: String? = nil) {
        self.id = id
        switch content {
        case .text(let value): self.content = .text(String(value.prefix(20_000)))
        case .image(let data): self.content = .image(Data(data.prefix(5_000_000)))
        case .files(let paths): self.content = .files(Array(paths.prefix(100)))
        }
        self.copiedAt = copiedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
    init(id: UUID = UUID(), text: String, copiedAt: Date = .now, sourceBundleIdentifier: String? = nil) {
        self.init(id: id, content: .text(text), copiedAt: copiedAt, sourceBundleIdentifier: sourceBundleIdentifier)
    }
    var text: String {
        switch content { case .text(let value): value; case .files(let paths): paths.joined(separator: "\n"); case .image: "Image" }
    }
    var typeName: String { switch content { case .text: "Text"; case .image: "Image"; case .files: "Files" } }

    private enum CodingKeys: String, CodingKey { case id, content, text, copiedAt, sourceBundleIdentifier }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        if let decoded = try container.decodeIfPresent(Content.self, forKey: .content) { content = decoded }
        else { content = .text(try container.decode(String.self, forKey: .text)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(copiedAt, forKey: .copiedAt)
        try container.encodeIfPresent(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
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
