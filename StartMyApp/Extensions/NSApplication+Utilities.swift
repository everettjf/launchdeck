import AppKit

extension NSApplication {
    func presentSettings() {
        if #available(macOS 13, *) {
            sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
