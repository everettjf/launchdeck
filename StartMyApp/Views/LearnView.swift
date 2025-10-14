import SwiftUI
import AppKit



class LearnUtils {
    
    public static func searchOnGoogle(_ query: String) {
        let searchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.google.com/search?q=\(searchQuery)") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func searchOnBing(_ query: String) {
        let searchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.bing.com/search?q=\(searchQuery)") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func searchOnDuckDuckGo(_ query: String) {
        let searchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://duckduckgo.com/?q=\(searchQuery)") {
            NSWorkspace.shared.open(url)
        }
    }
}



struct LearnView: View {
    let app: DiscoveredApp?
    @State private var selectedTab = 0
    @State private var frameworks: [FrameworkItem] = []
    @State private var resources: [ResourceItem] = []
    @State private var appInfo: AppInfoData?
    @State private var isLoading = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let app = app {
                // Header
                headerView(for: app)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(headerBackground)

                Divider()

                // Tab View
                TabView(selection: $selectedTab) {
                    appInfoTab
                        .tabItem {
                            Label("App Info", systemImage: "info.circle.fill")
                        }
                        .tag(0)

                    frameworksTab
                        .tabItem {
                            Label("Frameworks", systemImage: "shippingbox.fill")
                        }
                        .tag(1)

                    resourcesTab
                        .tabItem {
                            Label("Resources", systemImage: "folder.fill")
                        }
                        .tag(2)
                }
                .padding(.top, 8)
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadData()
        }
        .onChange(of: app) { _, _ in
            loadData()
        }
    }

    // MARK: - Header View
    private func headerView(for app: DiscoveredApp) -> some View {
        HStack(spacing: 16) {
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            Image(nsImage: icon)
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)

                Text(app.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var headerBackground: some View {
        Color(nsColor: colorScheme == .dark
              ? NSColor.windowBackgroundColor.blended(withFraction: 0.05, of: .white)!
              : NSColor.windowBackgroundColor.blended(withFraction: 0.02, of: .black)!)
    }

    // MARK: - App Info Tab
    private var appInfoTab: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = appInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Basic Info Section
                        infoSection(title: "Basic Information") {
                            VStack(spacing: 12) {
                                infoRow(label: "Name", value: info.app.name)
                                if let bundleIdentifier = info.app.bundleIdentifier {
                                    infoRow(label: "Bundle Identifier", value: bundleIdentifier)
                                }
                                if let version = info.app.bundleVersion {
                                    infoRow(label: "Version", value: version)
                                }
                                if let developer = info.app.developer {
                                    infoRow(label: "Developer", value: developer)
                                }
                                if let category = info.app.category {
                                    infoRow(label: "Category", value: category)
                                }
                                infoRow(label: "System Application", value: info.app.isSystemApp ? "Yes" : "No")
                            }
                        }

                        // File Info Section
                        infoSection(title: "File Information") {
                            VStack(spacing: 12) {
                                infoRow(label: "Path", value: info.app.path, isPath: true)
                                if let bundleSize = info.bundleSize {
                                    infoRow(label: "Bundle Size", value: bundleSize)
                                }
                                if let created = info.created {
                                    infoRow(label: "Created", value: formatDate(created))
                                }
                                if let modified = info.modified {
                                    infoRow(label: "Last Modified", value: formatDate(modified))
                                }
                                if let permissions = info.permissions {
                                    infoRow(label: "Permissions", value: permissions)
                                }
                            }
                        }

                        // Keywords Section
                        if !info.app.keywords.isEmpty {
                            infoSection(title: "Keywords") {
                                FlowLayout(spacing: 8) {
                                    ForEach(info.app.keywords.sorted(), id: \.self) { keyword in
                                        Text(keyword)
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // Actions Section
                        HStack(spacing: 12) {
                            Button(action: {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: info.app.path)])
                            }) {
                                Label("Show in Finder", systemImage: "folder")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(info.formattedDetails, forType: .string)
                            }) {
                                Label("Copy Details", systemImage: "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.large)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 20)
                }
            }
        }
    }

    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private func infoRow(label: String, value: String, isPath: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            if isPath {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Frameworks Tab
    private var frameworksTab: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if frameworks.isEmpty {
                emptyContentView(
                    icon: "shippingbox",
                    message: "No frameworks found",
                    description: "This application doesn't contain any frameworks or dynamic libraries."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(frameworks) { framework in
                            FrameworkRow(framework: framework)
                                .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Resources Tab
    private var resourcesTab: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if resources.isEmpty {
                emptyContentView(
                    icon: "folder",
                    message: "No resources found",
                    description: "This application doesn't contain any resources."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(resources) { resource in
                            ResourceRow(resource: resource)
                                .background(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Empty States
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Application Selected")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("Right-click on an app and select 'Learn' to explore its contents")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyContentView(icon: String, message: String, description: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(message)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading
    private func loadData() {
        guard let app = app else {
            isLoading = false
            return
        }

        isLoading = true
        frameworks = []
        resources = []
        appInfo = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let loadedFrameworks = scanFrameworks(appPath: app.path)
            let loadedResources = scanResources(appPath: app.path)
            let loadedAppInfo = loadAppInfo(app: app)

            DispatchQueue.main.async {
                self.frameworks = loadedFrameworks
                self.resources = loadedResources
                self.appInfo = loadedAppInfo
                self.isLoading = false
            }
        }
    }

    private func loadAppInfo(app: DiscoveredApp) -> AppInfoData {
        let fileURL = URL(fileURLWithPath: app.path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)

        return AppInfoData(
            app: app,
            bundleSize: attributes.flatMap { attrs in
                guard let size = attrs[.size] as? NSNumber else { return nil }
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: size.int64Value)
            },
            created: attributes?[.creationDate] as? Date,
            modified: attributes?[.modificationDate] as? Date,
            permissions: permissionsString(for: fileURL.path)
        )
    }

    private func permissionsString(for path: String) -> String? {
        var components: [String] = []
        if FileManager.default.isReadableFile(atPath: path) { components.append("Read") }
        if FileManager.default.isWritableFile(atPath: path) { components.append("Write") }
        if FileManager.default.isExecutableFile(atPath: path) { components.append("Execute") }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }

    private func scanFrameworks(appPath: String) -> [FrameworkItem] {
        let frameworksPath = (appPath as NSString).appendingPathComponent("Contents/Frameworks")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: frameworksPath) else {
            return []
        }

        return items
            .filter { $0.hasSuffix(".framework") || $0.hasSuffix(".dylib") }
            .sorted()
            .map { name in
                let fullPath = (frameworksPath as NSString).appendingPathComponent(name)
                return FrameworkItem(name: name, path: fullPath)
            }
    }

    private func scanResources(appPath: String) -> [ResourceItem] {
        let resourcesPath = (appPath as NSString).appendingPathComponent("Contents/Resources")
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: resourcesPath) else {
            return []
        }

        return items
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { name in
                let fullPath = (resourcesPath as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)

                return ResourceItem(name: name, path: fullPath, isDirectory: isDirectory.boolValue)
            }
    }
}

// MARK: - Framework Item
struct FrameworkItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String

    var displayName: String {
        if name.hasSuffix(".framework") {
            return String(name.dropLast(".framework".count))
        } else if name.hasSuffix(".dylib") {
            return String(name.dropLast(".dylib".count))
        }
        return name
    }

    var type: String {
        if name.hasSuffix(".framework") {
            return "Framework"
        } else if name.hasSuffix(".dylib") {
            return "Dynamic Library"
        }
        return "Unknown"
    }
}

// MARK: - Framework Row
struct FrameworkRow: View {
    let framework: FrameworkItem
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: framework.type == "Framework" ? "shippingbox.fill" : "doc.fill")
                .font(.system(size: 20))
                .foregroundColor(framework.type == "Framework" ? .blue : .purple)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(framework.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(framework.type)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Search icon (appears on hover)
            if isHovering {
                Button(action: { LearnUtils.searchOnGoogle(framework.displayName) }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Search on Google")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            LearnUtils.searchOnGoogle(framework.name)
        }
        .contextMenu {
            Button("Search with Google") {
                LearnUtils.searchOnGoogle(framework.name)
            }
            Button("Search with Bing") {
                LearnUtils.searchOnBing(framework.name)
            }
            Button("Search with DuckDuckGo") {
                LearnUtils.searchOnDuckDuckGo(framework.name)
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: framework.path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(framework.path, forType: .string)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering
                  ? Color(nsColor: colorScheme == .dark ? .white.withAlphaComponent(0.08) : .black.withAlphaComponent(0.04))
                  : Color.clear)
    }

}

// MARK: - Resource Item
struct ResourceItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic":
            return "photo.fill"
        case "icns", "ico":
            return "app.fill"
        case "pdf":
            return "doc.text.fill"
        case "txt", "rtf":
            return "doc.text"
        case "plist":
            return "list.bullet.rectangle"
        case "strings":
            return "character.bubble"
        default:
            return "doc.fill"
        }
    }

    var iconColor: Color {
        if isDirectory {
            return .blue
        }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "tiff", "bmp", "heic":
            return .green
        case "icns", "ico":
            return .orange
        case "pdf":
            return .red
        case "plist":
            return .purple
        case "strings":
            return .cyan
        default:
            return .gray
        }
    }
}

// MARK: - Resource Row
struct ResourceRow: View {
    let resource: ResourceItem
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: resource.icon)
                .font(.system(size: 20))
                .foregroundColor(resource.iconColor)
                .frame(width: 32)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(resource.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(resource.isDirectory ? "Folder" : "File")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Open icon (appears on hover)
            if isHovering {
                Button(action: { openResource() }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            openResource()
        }
        .contextMenu {
            
            Button("Open") {
                openResource()
            }
            Divider()
            
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: resource.path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resource.path, forType: .string)
            }
            
            Divider()
        
            Button("Search with Google") {
                LearnUtils.searchOnGoogle(resource.name)
            }
            Button("Search with Bing") {
                LearnUtils.searchOnBing(resource.name)
            }
            Button("Search with DuckDuckGo") {
                LearnUtils.searchOnDuckDuckGo(resource.name)
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering
                  ? Color(nsColor: colorScheme == .dark ? .white.withAlphaComponent(0.08) : .black.withAlphaComponent(0.04))
                  : Color.clear)
    }

    private func openResource() {
        NSWorkspace.shared.open(URL(fileURLWithPath: resource.path))
    }
    
    
}

// MARK: - FlowLayout for Keywords
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                sizes.append(size)
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview {
    LearnView(app: nil)
        .frame(width: 700, height: 500)
}
