import LaunchDeckCore

struct SearchSelection: Equatable, Sendable {
    private(set) var selectedIdentifier: String?

    mutating func reconcile(items: [SearchItem]) {
        guard let first = items.first else {
            selectedIdentifier = nil
            return
        }
        if let selectedIdentifier, items.contains(where: { $0.id == selectedIdentifier }) { return }
        selectedIdentifier = first.id
    }

    mutating func move(by offset: Int, items: [SearchItem]) {
        guard !items.isEmpty else {
            selectedIdentifier = nil
            return
        }
        let currentIndex = selectedIdentifier.flatMap { selected in
            items.firstIndex(where: { $0.id == selected })
        } ?? 0
        let destination = min(max(currentIndex + offset, 0), items.count - 1)
        selectedIdentifier = items[destination].id
    }

    func selectedItem(in items: [SearchItem]) -> SearchItem? {
        guard let selectedIdentifier else { return items.first }
        return items.first(where: { $0.id == selectedIdentifier }) ?? items.first
    }
}
