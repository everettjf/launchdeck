import AppKit

enum AppInfoPresenter {
    static func present(for app: DiscoveredApp) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = app.name

        var details: [String] = []
        if let bundleIdentifier = app.bundleIdentifier {
            details.append("Bundle ID: \(bundleIdentifier)")
        }
        details.append("Path: \(app.path)")
        if let version = app.bundleVersion {
            details.append("Version: \(version)")
        }
        if let developer = app.developer {
            details.append("Developer: \(developer)")
        }
        if let category = app.category {
            details.append("Category: \(category)")
        }
        details.append("System App: \(app.isSystemApp ? "Yes" : "No")")

        if !app.keywords.isEmpty {
            details.append("Keywords: \(app.keywords.joined(separator: ", "))")
        }

        alert.informativeText = details.joined(separator: "\n")

        let accessory = createAccessoryView(for: app)
        alert.accessoryView = accessory

        alert.addButton(withTitle: "Open in Finder")
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Path")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
        case .alertThirdButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.path, forType: .string)
        default:
            break
        }
    }

    private static func createAccessoryView(for app: DiscoveredApp) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let icon = NSWorkspace.shared.icon(forFile: app.path).copy() as? NSImage {
            icon.size = NSSize(width: 64, height: 64)
            let imageView = NSImageView(image: icon)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            stack.addArrangedSubview(imageView)
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: app.path) {
            if let modificationDate = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let label = NSTextField(labelWithString: "Modified: \(formatter.string(from: modificationDate))")
                stack.addArrangedSubview(label)
            }
            if let size = attributes[.size] as? NSNumber {
                let byteCountFormatter = ByteCountFormatter()
                byteCountFormatter.allowedUnits = [.useMB, .useGB]
                byteCountFormatter.countStyle = .file
                let label = NSTextField(labelWithString: "Size: \(byteCountFormatter.string(fromByteCount: size.int64Value))")
                stack.addArrangedSubview(label)
            }
        }

        let permissions = permissionsString(for: app.path)
        if !permissions.isEmpty {
            let label = NSTextField(labelWithString: "Permissions: \(permissions)")
            stack.addArrangedSubview(label)
        }

        return stack
    }

    private static func permissionsString(for path: String) -> String {
        var result: [String] = []
        let fileManager = FileManager.default
        if fileManager.isReadableFile(atPath: path) {
            result.append("Read")
        }
        if fileManager.isWritableFile(atPath: path) {
            result.append("Write")
        }
        if fileManager.isExecutableFile(atPath: path) {
            result.append("Execute")
        }
        return result.joined(separator: "/")
    }
}
