import SwiftUI

struct AIProviderSettingsView: View {
    @Bindable var store: AIProviderSettingsStore

    var body: some View {
        Section("External AI Provider") {
            Toggle("Enable provider", isOn: $store.configuration.isEnabled)
            Picker("Protocol", selection: $store.configuration.kind) {
                ForEach(AIProviderKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
            }
            .onChange(of: store.configuration.kind) { _, kind in
                store.configuration.endpoint = kind.defaultEndpoint
                store.configuration.name = kind == .anthropic ? "Anthropic" : "OpenAI"
            }
            TextField("Display name", text: $store.configuration.name)
            TextField("Endpoint", text: $store.configuration.endpoint)
                .textContentType(.URL)
            TextField("Model", text: $store.configuration.model)
            SecureField("API key (optional for localhost)", text: $store.APIKey)
                .textContentType(.password)
            if let message = store.configuration.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                Button("Save") { store.save() }
                Button(store.isTesting ? "Testing…" : "Test Connection") { Task { await store.testConnection() } }
                    .disabled(store.isTesting)
                Button("Remove Key", role: .destructive) { store.removeKey() }.disabled(store.APIKey.isEmpty)
            }
            Text(store.status).font(.caption).foregroundStyle(.secondary)
            Text("Remote endpoints require HTTPS. HTTP is accepted only for localhost, 127.0.0.1, or ::1.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
