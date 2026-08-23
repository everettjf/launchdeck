import Foundation
import LaunchDeckCore

enum SearchCatalogBuilder {
    static func build(apps: [DiscoveredApp], indexedItems: [SearchItem],
                      approvedShortcuts: [String], recipes: [Recipe],
                      registry: ActionRegistry = .shared) -> [SearchItem] {
        var items = apps.map { app in
            SearchItem(id: "application:\(app.identifier)", kind: .application, title: app.name,
                       subtitle: app.developer ?? app.category,
                       keywords: app.keywords + [app.bundleIdentifier ?? ""],
                       target: .application(identifier: app.identifier, path: app.path))
        }
        items += indexedItems
        items += SystemSettingsDestination.allCases.map {
            SearchItem(id: "setting:\($0.rawValue)", kind: .setting, title: $0.title,
                       keywords: ["settings", "preferences"], target: .systemSetting(identifier: $0.rawValue))
        }
        items += approvedShortcuts.map {
            SearchItem(id: "shortcut:\($0)", kind: .shortcut, title: $0, subtitle: "Approved Shortcut",
                       keywords: ["shortcut", "automation"], target: .shortcut(name: $0))
        }
        items += recipes.map {
            SearchItem(id: "recipe:\($0.id.uuidString)", kind: .recipe, title: $0.name,
                       subtitle: "\($0.steps.count) steps", keywords: ["recipe", "workflow"],
                       target: .recipe(identifier: $0.id))
        }
        items += registry.descriptors.map {
            SearchItem(id: "action:\($0.id)", kind: .action, title: $0.title,
                       subtitle: $0.requiredParameters.isEmpty ? "Ready" : "Parameters: \($0.requiredParameters.sorted().joined(separator: ", "))",
                       keywords: ["action", "command"], target: .registeredAction(identifier: $0.id))
        }
        return items
    }
}
