import LaunchDeckCore
import Testing
@testable import LaunchDeck

struct SearchSelectionTests {
    private func item(_ id: String) -> SearchItem {
        SearchItem(id: id, kind: .application, title: id,
                   target: .application(identifier: id, path: "/Applications/\(id).app"))
    }

    @Test func reconciliationSelectsFirstResultAndPreservesStableSelection() {
        var selection = SearchSelection()
        selection.reconcile(items: [item("a"), item("b")])
        #expect(selection.selectedIdentifier == "a")

        selection.move(by: 1, items: [item("a"), item("b")])
        selection.reconcile(items: [item("c"), item("b")])
        #expect(selection.selectedIdentifier == "b")
    }

    @Test func reconciliationFallsBackWhenSelectedResultDisappears() {
        var selection = SearchSelection()
        let initial = [item("a"), item("b")]
        selection.reconcile(items: initial)
        selection.move(by: 1, items: initial)
        selection.reconcile(items: [item("c"), item("d")])
        #expect(selection.selectedIdentifier == "c")
    }

    @Test func movementClampsAtBothEdges() {
        var selection = SearchSelection()
        let items = [item("a"), item("b"), item("c")]
        selection.reconcile(items: items)
        selection.move(by: -10, items: items)
        #expect(selection.selectedIdentifier == "a")
        selection.move(by: 20, items: items)
        #expect(selection.selectedIdentifier == "c")
    }

    @Test func emptyResultsClearSelection() {
        var selection = SearchSelection()
        selection.reconcile(items: [item("a")])
        selection.reconcile(items: [])
        #expect(selection.selectedIdentifier == nil)
        #expect(selection.selectedItem(in: []) == nil)
    }
}
