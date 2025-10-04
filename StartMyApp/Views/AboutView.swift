import AppKit
import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© \(Calendar.current.component(.year, from: Date()))"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .cornerRadius(20)
                    .shadow(radius: 8)
            }

            Text(Bundle.main.appDisplayName)
                .font(.title2.weight(.semibold))

            Text(appVersion)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                Link("Support & Feedback", destination: URL(string: "https://startmy.app")!)
                Link("Privacy Policy", destination: URL(string: "https://startmy.app/privacy")!)
            }

            Divider()

            Text(copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360)
    }
}
