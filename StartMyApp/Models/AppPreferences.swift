import Combine
import SwiftUI

final class AppPreferences: ObservableObject {
    enum GridScale: Int, CaseIterable {
        case compact
        case comfortable
        case spacious

        var title: String {
            switch self {
            case .compact: return "Compact"
            case .comfortable: return "Comfortable"
            case .spacious: return "Spacious"
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .compact: return 48
            case .comfortable: return 60
            case .spacious: return 76
            }
        }

        var labelFontSize: CGFloat {
            switch self {
            case .compact: return 11
            case .comfortable: return 12.5
            case .spacious: return 14.5
            }
        }

        var horizontalSpacing: CGFloat {
            switch self {
            case .compact: return 12
            case .comfortable: return 16
            case .spacious: return 20
            }
        }

        var verticalSpacing: CGFloat {
            switch self {
            case .compact: return 16
            case .comfortable: return 22
            case .spacious: return 28
            }
        }

        var minimumTileWidth: CGFloat {
            iconSize + 28
        }

        var maximumTileWidth: CGFloat {
            iconSize + 110
        }
    }

    enum SortOption: Int, CaseIterable, Identifiable {
        case custom
        case alphabetical
        case mostLaunched
        case recentlyLaunched

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .custom: return "Custom"
            case .alphabetical: return "Name"
            case .mostLaunched: return "Most Launched"
            case .recentlyLaunched: return "Recently Launched"
            }
        }

        var shortLabel: String {
            switch self {
            case .custom: return "Sort: Custom"
            case .alphabetical: return "Sort: Name"
            case .mostLaunched: return "Sort: Most Launched"
            case .recentlyLaunched: return "Sort: Recent"
            }
        }

        var iconName: String {
            switch self {
            case .custom: return "arrow.uturn.backward"
            case .alphabetical: return "textformat"
            case .mostLaunched: return "flame"
            case .recentlyLaunched: return "clock.arrow.circlepath"
            }
        }
    }

    @Published var showSystemApps: Bool
    @Published var gridScale: GridScale
    @Published var sortOption: SortOption

    private let defaults: UserDefaults
    fileprivate var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let showSystemApps = "preferences.showSystemApps"
        static let gridScale = "preferences.gridScale"
        static let sortOption = "preferences.sortOption"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.showSystemApps) == nil {
            defaults.set(false, forKey: Keys.showSystemApps)
        }
        showSystemApps = defaults.bool(forKey: Keys.showSystemApps)

        let storedScale = defaults.integer(forKey: Keys.gridScale)
        gridScale = GridScale(rawValue: storedScale) ?? .comfortable

        let storedSort = defaults.integer(forKey: Keys.sortOption)
        sortOption = SortOption(rawValue: storedSort) ?? .custom

        bind()
    }

    private func bind() {
        $showSystemApps
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.showSystemApps)
            }
            .store(in: &cancellables)

        $gridScale
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.gridScale)
            }
            .store(in: &cancellables)

        $sortOption
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.sortOption)
            }
            .store(in: &cancellables)
    }
}
