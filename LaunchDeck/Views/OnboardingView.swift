import AppKit
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private let pages = ["Welcome", "Instant Send", "Private Clipboard", "Local Index"]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index <= page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 5)
                        .accessibilityLabel("Step \(index + 1), \(pages[index])")
                }
            }
            pageContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Spacer()
                Button(page == pages.count - 1 ? "Start Using LaunchDeck" : "Continue") {
                    if page == pages.count - 1 { preferences.hasCompletedOnboarding = true }
                    else { page += 1 }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 620, height: 480)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case 0:
            onboardingPage(icon: "paperplane.circle.fill", title: "Send anything. Do anything.",
                           detail: "LaunchDeck combines instant local search with a transparent Object → Action → Target workflow. Every file-changing action is previewed, and supported operations can be undone.") {
                Label("Search remains fully functional without AI or a network connection.", systemImage: "lock.shield")
            }
        case 1:
            onboardingPage(icon: "command.circle.fill", title: "Capture your current context",
                           detail: "Use the global shortcut while Finder, Safari, Chrome, or another app is frontmost. LaunchDeck captures selected files, the current URL, or selected text before opening.") {
                Toggle("Enable Global Shortcut", isOn: $preferences.isGlobalShortcutEnabled)
                ShortcutRecorderView(shortcut: $preferences.globalShortcut)
            }
        case 2:
            onboardingPage(icon: "clipboard.fill", title: "Clipboard history is opt-in",
                           detail: "When enabled, text, images up to 5 MB, and up to 100 file references per entry remain on this Mac. Password managers and excluded apps are ignored.") {
                Toggle("Enable Private Clipboard History", isOn: Binding(get: { preferences.clipboardEnabled }, set: {
                    preferences.clipboardEnabled = $0
                    if $0 { preferences.clipboardDisclosureAcknowledged = true }
                }))
                Text("You can clear all behavioral data or change retention at any time in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            onboardingPage(icon: "externaldrive.fill", title: "Choose what LaunchDeck indexes",
                           detail: "Application discovery is automatic. Add only the document or project folders you want available in local search.") {
                ForEach(preferences.indexedRootPaths, id: \.self) { Text($0).font(.caption).lineLimit(1) }
                Button("Add Search Folder…", action: chooseFolder)
            }
        }
    }

    private func onboardingPage<Content: View>(icon: String, title: String, detail: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon).font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
            Text(title).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
            Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500)
            GroupBox { VStack(alignment: .leading, spacing: 12, content: content).padding(6) }.frame(maxWidth: 500)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(appState.addIndexedRoot)
    }
}
