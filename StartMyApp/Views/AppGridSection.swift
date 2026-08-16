import SwiftUI
import LaunchDeckCore

struct AppGridSection<HeaderTrailing: View>: View {
    let title: String
    let apps: [DiscoveredApp]
    let emptyState: String?
    @ViewBuilder var trailing: () -> HeaderTrailing

    @EnvironmentObject private var preferences: AppPreferences

    init(title: String,
         apps: [DiscoveredApp],
         emptyState: String? = nil,
         @ViewBuilder trailing: @escaping () -> HeaderTrailing = { EmptyView() }) {
        self.title = title
        self.apps = apps
        self.emptyState = emptyState
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                trailing()
            }
            if apps.isEmpty {
                if let emptyState {
                    Text(emptyState)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: preferences.gridScale.verticalSpacing) {
                    ForEach(apps, id: \.identifier) { app in
                        AppTile(app: app)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: preferences.gridScale.minimumTileWidth,
                             maximum: preferences.gridScale.maximumTileWidth),
                  spacing: preferences.gridScale.horizontalSpacing,
                  alignment: .top)]
    }
}
