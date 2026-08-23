import Combine
import CryptoKit
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

    func install(data: Data, allowPermissionExpansion: Bool = false) throws {
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        let errors = ExtensionManifestValidation.errors(in: manifest)
        guard errors.isEmpty else { throw ExtensionStoreError.invalid(errors.joined(separator: "\n")) }
        if let minimum = manifest.minimumLaunchDeckVersion,
           compareVersions(minimum, currentLaunchDeckVersion) == .orderedDescending {
            throw ExtensionStoreError.incompatible("Requires LaunchDeck \(minimum) or later.")
        }
        if let existing = manifests.first(where: { $0.id == manifest.id }) {
            guard compareVersions(manifest.version, existing.version) != .orderedAscending else {
                throw ExtensionStoreError.downgrade(existing: existing.version, proposed: manifest.version)
            }
            let added = manifest.permissions.subtracting(existing.permissions)
            if !added.isEmpty, !allowPermissionExpansion { throw ExtensionStoreError.permissionExpansion(added) }
        }
        let target = directory.appendingPathComponent(manifest.id, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try data.write(to: target.appendingPathComponent("manifest.json"), options: .atomic)
        let record = ExtensionInstallationRecord(version: manifest.version,
                                                 sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                                                 installedAt: .now)
        try JSONEncoder().encode(record).write(to: target.appendingPathComponent("installation.json"), options: .atomic)
        reload()
    }

    func uninstall(id: String) throws {
        guard manifests.contains(where: { $0.id == id }) else { return }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id, isDirectory: true))
        reload()
    }

    func exportData(id: String) throws -> Data {
        guard manifests.contains(where: { $0.id == id }) else {
            throw ExtensionStoreError.invalid("The extension is no longer installed.")
        }
        return try Data(contentsOf: directory.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("manifest.json"))
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

    private var currentLaunchDeckVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.0"
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}

nonisolated struct ExtensionInstallationRecord: Codable, Hashable, Sendable {
    let version: String
    let sha256: String
    let installedAt: Date
}

enum ExtensionStoreError: LocalizedError, Equatable {
    case invalid(String)
    case incompatible(String)
    case downgrade(existing: String, proposed: String)
    case permissionExpansion(Set<ExtensionManifest.Permission>)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .incompatible(let message): message
        case .downgrade(let existing, let proposed): "Refusing to downgrade extension from \(existing) to \(proposed)."
        case .permissionExpansion(let permissions):
            "This update adds permissions: \(permissions.map(\.rawValue).sorted().joined(separator: ", "))."
        }
    }
}
