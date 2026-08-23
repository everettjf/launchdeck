import Combine
import Foundation

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet]
    private let defaults: UserDefaults
    private let key = "snippets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snippets = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
    }

    func save(_ snippet: Snippet) throws {
        guard !snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !snippet.content.isEmpty else { throw SnippetStoreError.invalid }
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) { snippets[index] = snippet }
        else { snippets.append(snippet) }
        persist()
    }
    func remove(id: UUID) { snippets.removeAll { $0.id == id }; persist() }
    private func persist() { defaults.set(try? JSONEncoder().encode(snippets), forKey: key) }
}

enum SnippetStoreError: LocalizedError {
    case invalid
    var errorDescription: String? { "Snippet name and content are required." }
}
