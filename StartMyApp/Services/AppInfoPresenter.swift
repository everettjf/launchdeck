import AppKit

enum AppInfoPresenter {
    static func present(for app: DiscoveredApp) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = app.name
        alert.informativeText = "Detailed application metadata"

        let detailsString = details(for: app)
        alert.accessoryView = accessoryView(with: detailsString, iconPath: app.path)

        alert.addButton(withTitle: "Open in Finder")
        alert.addButton(withTitle: "Copy Details")
        alert.addButton(withTitle: "Close")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
        case .alertSecondButtonReturn:
            copyToPasteboard(detailsString)
        default:
            break
        }
    }

    private static func details(for app: DiscoveredApp) -> String {
        var lines: [String] = []
        lines.append("Name: \(app.name)")
        if let bundleIdentifier = app.bundleIdentifier {
            lines.append("Bundle Identifier: \(bundleIdentifier)")
        }
        if let version = app.bundleVersion {
            lines.append("Version: \(version)")
        }
        if let developer = app.developer {
            lines.append("Developer: \(developer)")
        }
        if let category = app.category {
            lines.append("Category: \(category)")
        }
        lines.append("System Application: \(app.isSystemApp ? "Yes" : "No")")
        lines.append("Path: \(app.path)")

        let url = URL(fileURLWithPath: app.path)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attributes[.size] as? NSNumber {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                lines.append("Bundle Size: \(formatter.string(fromByteCount: size.int64Value))")
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            if let creationDate = attributes[.creationDate] as? Date {
                lines.append("Created: \(dateFormatter.string(from: creationDate))")
            }
            if let modifiedDate = attributes[.modificationDate] as? Date {
                lines.append("Last Modified: \(dateFormatter.string(from: modifiedDate))")
            }
            let permissions = permissionsString(for: url.path)
            if !permissions.isEmpty {
                lines.append("Permissions: \(permissions)")
            }
        }

        if !app.keywords.isEmpty {
            lines.append("Keywords: \(app.keywords.sorted().joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private static func accessoryView(with details: String, iconPath: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let icon = NSWorkspace.shared.icon(forFile: iconPath).copy() as? NSImage {
            icon.size = NSSize(width: 64, height: 64)
            let imageView = NSImageView(image: icon)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            stack.addArrangedSubview(imageView)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 360).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = details

        scrollView.documentView = textView
        stack.addArrangedSubview(scrollView)

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

    private static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
