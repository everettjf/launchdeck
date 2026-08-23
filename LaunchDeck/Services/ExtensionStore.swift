import Combine
import Foundation
import LaunchDeckCore

@MainActor
final class ExtensionStore: ObservableObject {
    @Published private(set) var manifests: [ExtensionManifest] = []
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchDeck/Extensions", isDirectory: true)
        reload()
    }

    func install(data: Data) throws {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        let errors = ExtensionManifestValidation.errors(in: manifest)
        guard errors.isEmpty else { throw ExtensionStoreError.invalid(errors.joined(separator: "\n")) }
        let target = directory.appendingPathComponent(manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try data.write(to: target.appendingPathComponent("manifest.json"), options: .atomic)
        reload()
    }

    func uninstall(id: String) throws {
        guard manifests.contains(where: { $0.id == id }) else { return }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id, isDirectory: true))
        reload()
    }

    func searchItems(matching rawQuery: String) -> [SearchItem] {
        let query = rawQuery.lowercased()
        return manifests.flatMap { manifest in
            manifest.commands.compactMap { command in
                switch command.kind {
                case .quicklink:
                    guard let keyword = command.keyword?.lowercased(), query.hasPrefix(keyword + " ") else { return nil }
                    let term = String(rawQuery.dropFirst(keyword.count + 1))
                    guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let url = URL(string: command.value.replacingOccurrences(of: "{query}", with: encoded)) else { return nil }
                    return SearchItem(id: "extension:\(manifest.id):\(command.id):\(term)", kind: .extensionCommand,
                                      title: command.name, subtitle: manifest.name, keywords: [keyword, manifest.name], target: .url(url))
                case .openURL:
                    guard command.name.lowercased().contains(query) || manifest.name.lowercased().contains(query),
                          let url = URL(string: command.value) else { return nil }
                    return SearchItem(id: "extension:\(manifest.id):\(command.id)", kind: .extensionCommand,
                                      title: command.name, subtitle: manifest.name, keywords: [manifest.name], target: .url(url))
                case .staticText:
                    guard command.name.lowercased().contains(query) || command.value.lowercased().contains(query) else { return nil }
                    return SearchItem(id: "extension:\(manifest.id):\(command.id)", kind: .extensionCommand,
                                      title: command.name, subtitle: manifest.name, keywords: [manifest.name], target: .copyText(command.value))
                }
            }
        }
    }

    private func reload() {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            manifests = []
            return
        }
        manifests = children.compactMap { try? Data(contentsOf: $0.appendingPathComponent("manifest.json")) }
            .compactMap { try? JSONDecoder().decode(ExtensionManifest.self, from: $0) }
            .filter { ExtensionManifestValidation.errors(in: $0).isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum ExtensionStoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
