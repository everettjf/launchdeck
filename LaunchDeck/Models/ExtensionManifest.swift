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
    let permissions: Set<Permission>
    let commands: [Command]
}

nonisolated enum ExtensionManifestValidation {
    static func errors(in manifest: ExtensionManifest) -> [String] {
        var errors: [String] = []
        if manifest.schemaVersion != 1 { errors.append("Only manifest schemaVersion 1 is supported.") }
        let identifierPattern = #"^[A-Za-z][A-Za-z0-9.-]{2,127}$"#
        if manifest.id.range(of: identifierPattern, options: .regularExpression) == nil { errors.append("Extension id is invalid.") }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Extension name is required.") }
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
}
