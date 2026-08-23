import Combine
import Foundation

@MainActor
final class QuicklinkStore: ObservableObject {
    @Published private(set) var quicklinks: [Quicklink]
    private let defaults: UserDefaults
    private let key = "quicklinks.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quicklinks = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Quicklink].self, from: $0) }
            ?? Self.builtIns
    }

    func save(_ quicklink: Quicklink) throws {
        if let error = QuicklinkValidation.error(for: quicklink) { throw QuicklinkStoreError.invalid(error) }
        guard !quicklinks.contains(where: { $0.id != quicklink.id && $0.keyword.caseInsensitiveCompare(quicklink.keyword) == .orderedSame }) else {
            throw QuicklinkStoreError.invalid("Quicklink keywords must be unique.")
        }
        if let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) { quicklinks[index] = quicklink }
        else { quicklinks.append(quicklink) }
        persist()
    }

    func remove(id: UUID) { quicklinks.removeAll { $0.id == id }; persist() }

    private func persist() { defaults.set(try? JSONEncoder().encode(quicklinks), forKey: key) }

    static let builtIns = [
        Quicklink(name: "Google", keyword: "g", urlTemplate: "https://www.google.com/search?q={query}"),
        Quicklink(name: "DuckDuckGo", keyword: "ddg", urlTemplate: "https://duckduckgo.com/?q={query}"),
        Quicklink(name: "Wikipedia", keyword: "wiki", urlTemplate: "https://en.wikipedia.org/wiki/Special:Search?search={query}"),
    ]
}

enum QuicklinkStoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
