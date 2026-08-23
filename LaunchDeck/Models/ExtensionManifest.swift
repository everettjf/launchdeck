import Foundation

nonisolated struct ExtensionManifest: Codable, Hashable, Identifiable, Sendable {
    enum Permission: String, Codable, CaseIterable, Hashable, Sendable { case network, files, processes }
    struct Command: Codable, Hashable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case quicklink, staticText, openURL }
        let id: String
        let name: String
        let kind: Kind
        let value: String
        let keyword: String?
    }
    let schemaVersion: Int
    let id: String
    let name: String
    let version: String
    let minimumLaunchDeckVersion: String?
    let publisher: String?
    let permissions: Set<Permission>
    let commands: [Command]

    init(schemaVersion: Int, id: String, name: String, version: String,
         minimumLaunchDeckVersion: String? = nil, publisher: String? = nil,
         permissions: Set<Permission>, commands: [Command]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.minimumLaunchDeckVersion = minimumLaunchDeckVersion
        self.publisher = publisher
        self.permissions = permissions
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, version, minimumLaunchDeckVersion, publisher, permissions, commands
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        minimumLaunchDeckVersion = try container.decodeIfPresent(String.self, forKey: .minimumLaunchDeckVersion)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        permissions = try container.decode(Set<Permission>.self, forKey: .permissions)
        commands = try container.decode([Command].self, forKey: .commands)
    }
}

nonisolated enum ExtensionManifestValidation {
    static func errors(in manifest: ExtensionManifest) -> [String] {
        var errors: [String] = []
        if !(1...2).contains(manifest.schemaVersion) { errors.append("Only manifest schemaVersion 1 and 2 are supported.") }
        let identifierPattern = #"^[A-Za-z][A-Za-z0-9.-]{2,127}$"#
        if manifest.id.range(of: identifierPattern, options: .regularExpression) == nil { errors.append("Extension id is invalid.") }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Extension name is required.") }
        if !isSemanticVersion(manifest.version) { errors.append("Extension version must use semantic versioning.") }
        if let minimum = manifest.minimumLaunchDeckVersion, !isSemanticVersion(minimum) {
            errors.append("minimumLaunchDeckVersion must use semantic versioning.")
        }
        if manifest.commands.isEmpty { errors.append("At least one command is required.") }
        if Set(manifest.commands.map(\.id)).count != manifest.commands.count { errors.append("Command ids must be unique.") }
        for command in manifest.commands {
            switch command.kind {
            case .quicklink:
                if !manifest.permissions.contains(.network) { errors.append("Quicklink command \(command.id) requires network permission.") }
                if command.keyword?.isEmpty != false || !command.value.contains("{query}") { errors.append("Quicklink command \(command.id) needs a keyword and {query} template.") }
            case .openURL:
                if !manifest.permissions.contains(.network) { errors.append("URL command \(command.id) requires network permission.") }
                if !isWebURL(command.value) { errors.append("URL command \(command.id) must use HTTP or HTTPS.") }
            case .staticText:
                break
            }
        }
        return errors
    }

    private static func isWebURL(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil
    }
}
