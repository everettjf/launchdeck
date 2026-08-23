import Foundation
import Observation
import Security

nonisolated enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible
    case anthropic

    var title: String { self == .openAICompatible ? "OpenAI-compatible" : "Anthropic" }
    var defaultEndpoint: String {
        self == .openAICompatible ? "https://api.openai.com/v1/chat/completions" : "https://api.anthropic.com/v1/messages"
    }
}

nonisolated struct AIProviderConfiguration: Codable, Equatable, Sendable {
    var kind: AIProviderKind = .openAICompatible
    var name = "OpenAI"
    var endpoint = AIProviderKind.openAICompatible.defaultEndpoint
    var model = "gpt-4.1-mini"
    var isEnabled = false

    var validationMessage: String? {
        guard let URL = URL(string: endpoint), let scheme = URL.scheme?.lowercased(), let host = URL.host?.lowercased(), !model.isEmpty else {
            return "Enter a valid endpoint and model."
        }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && loopback) else {
            return "Remote providers must use HTTPS. HTTP is allowed only for localhost."
        }
        return nil
    }

    var isLoopback: Bool {
        guard let host = URL(string: endpoint)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

nonisolated struct AIProviderRuntimeConfiguration: Sendable {
    var configuration: AIProviderConfiguration
    var APIKey: String
}

nonisolated protocol AIProviderSecretStoring: Sendable {
    func load() throws -> String?
    func save(_ secret: String) throws
    func remove() throws
}

nonisolated final class KeychainAIProviderSecretStore: AIProviderSecretStoring, @unchecked Sendable {
    private let service = "com.everettjf.launchdeck.ai-provider"
    private let account = "default"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return String(data: data, encoding: .utf8)
    }

    func save(_ secret: String) throws {
        try remove()
        var query = baseQuery
        query[kSecValueData as String] = Data(secret.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)" }
    }
}

@MainActor
@Observable
final class AIProviderSettingsStore {
    var configuration: AIProviderConfiguration
    var APIKey = ""
    var status = "Not tested"
    var isTesting = false
    private let defaults: UserDefaults
    private let secrets: any AIProviderSecretStoring
    private let key = "workflow.ai.provider.v1"

    init(defaults: UserDefaults = .standard, secrets: any AIProviderSecretStoring = KeychainAIProviderSecretStore()) {
        self.defaults = defaults
        self.secrets = secrets
        configuration = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AIProviderConfiguration.self, from: $0) } ?? .init()
        APIKey = (try? secrets.load()) ?? ""
    }

    var runtimeConfiguration: AIProviderRuntimeConfiguration? {
        guard configuration.isEnabled, configuration.validationMessage == nil,
              configuration.isLoopback || !APIKey.isEmpty else { return nil }
        return .init(configuration: configuration, APIKey: APIKey)
    }

    func save() {
        guard configuration.validationMessage == nil else { status = configuration.validationMessage!; return }
        do {
            defaults.set(try JSONEncoder().encode(configuration), forKey: key)
            if APIKey.isEmpty { try secrets.remove() } else { try secrets.save(APIKey) }
            status = "Saved"
        } catch { status = error.localizedDescription }
    }

    func removeKey() {
        do { try secrets.remove(); APIKey = ""; status = "API key removed" }
        catch { status = error.localizedDescription }
    }

    func testConnection() async {
        guard let runtimeConfiguration else { status = configuration.validationMessage ?? "Enable the provider and enter an API key."; return }
        isTesting = true; defer { isTesting = false }
        do {
            _ = try await AIProviderClient.complete(prompt: "Return only this JSON: {\"ok\":true}",
                                                    instructions: "Return valid JSON.", provider: runtimeConfiguration)
            status = "Connected"
        } catch { status = error.localizedDescription }
    }
}

nonisolated enum AIProviderClient {
    enum ClientError: LocalizedError {
        case invalidConfiguration(String), HTTP(Int), invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalidConfiguration(let message): message
            case .HTTP(let code): "Provider request failed (HTTP \(code))."
            case .invalidResponse: "Provider returned an invalid response."
            }
        }
    }

    static func complete(prompt: String, instructions: String, provider: AIProviderRuntimeConfiguration,
                         session: URLSession = .shared) async throws -> String {
        let config = provider.configuration
        if let message = config.validationMessage { throw ClientError.invalidConfiguration(message) }
        guard config.isLoopback || !provider.APIKey.isEmpty else { throw ClientError.invalidConfiguration("An API key is required.") }
        guard let URL = URL(string: config.endpoint) else { throw ClientError.invalidConfiguration("Invalid endpoint.") }
        var request = URLRequest(url: URL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch config.kind {
        case .openAICompatible:
            if !provider.APIKey.isEmpty { request.setValue("Bearer \(provider.APIKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": config.model,
                "messages": [["role": "system", "content": instructions], ["role": "user", "content": prompt]],
                "temperature": 0.2
            ])
        case .anthropic:
            request.setValue(provider.APIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": config.model, "max_tokens": 2048, "system": instructions,
                "messages": [["role": "user", "content": prompt]]
            ])
        }
        let (data, response) = try await session.data(for: request)
        guard let HTTP = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(HTTP.statusCode) else { throw ClientError.HTTP(HTTP.statusCode) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.invalidResponse }
        let content: String? = switch config.kind {
        case .openAICompatible:
            ((object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        case .anthropic:
            (object["content"] as? [[String: Any]])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        }
        guard let content, !content.isEmpty else { throw ClientError.invalidResponse }
        return content
    }

    static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let result = try? JSONDecoder().decode(type, from: data) { return result }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start <= end,
              let data = String(trimmed[start...end]).data(using: .utf8) else { throw ClientError.invalidResponse }
        return try JSONDecoder().decode(type, from: data)
    }
}
