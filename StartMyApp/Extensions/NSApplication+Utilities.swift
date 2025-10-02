import AppKit

extension NSApplication {
    func presentSettings() {
        sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
