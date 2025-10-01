import SwiftUI

struct AppInfoView: View {
    let info: AppInfoData

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var icon: NSImage?

    private var monospacedFont: Font { .system(.body, design: .monospaced) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            ScrollView {
                Text(info.formattedDetails)
                    .font(monospacedFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(minHeight: 220, idealHeight: 260)

            HStack {
                Button {
                    appState.revealInFinder(info.app)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }

                Button {
                    appState.copyPathToClipboard(info.app)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                Button {
                    appState.copyDetails(of: info)
                } label: {
                    Label("Copy Details", systemImage: "list.bullet.rectangle")
                }

                Spacer()

                Button("Close") {
                    appState.dismissAppInfo()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 540, idealWidth: 600)
        .background(VisualEffectBackground())
        .onAppear(perform: loadIcon)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 4, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 72, height: 72)
                        .overlay(ProgressView())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(info.app.name)
                    .font(.title3.weight(.semibold))
                if let bundleIdentifier = info.app.bundleIdentifier {
                    Text(bundleIdentifier)
                        .font(monospacedFont)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func loadIcon() {
        AppIconCache.shared.icon(for: info.app.path, size: 96) { image in
            icon = image
        }
    }
}

#Preview {
    let preferences = AppPreferences()
    let state = AppState(preferences: preferences)
    let app = DiscoveredApp(name: "Preview App",
                            bundleIdentifier: "com.example.preview",
                            path: "/Applications/Preview.app",
                            category: "Productivity",
                            bundleVersion: "1.0",
                            developer: "Example",
                            isSystemApp: false,
                            keywords: ["Preview", "Example"])
    let info = AppInfoData(app: app,
                           bundleSize: "12.5 MB",
                           created: Date(),
                           modified: Date(),
                           permissions: "Read/Execute")
    return AppInfoView(info: info)
        .environmentObject(state)
}
