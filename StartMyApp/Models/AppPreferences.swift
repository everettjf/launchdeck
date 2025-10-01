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
            case .compact: return 52
            case .comfortable: return 68
            case .spacious: return 88
            }
        }

        var labelFontSize: CGFloat {
            switch self {
            case .compact: return 11
            case .comfortable: return 13
            case .spacious: return 15
            }
        }

        var horizontalSpacing: CGFloat {
            switch self {
            case .compact: return 14
            case .comfortable: return 18
            case .spacious: return 24
            }
        }

        var verticalSpacing: CGFloat {
            switch self {
            case .compact: return 18
            case .comfortable: return 24
            case .spacious: return 30
            }
        }

        var minimumTileWidth: CGFloat {
            iconSize + 48
        }

        var maximumTileWidth: CGFloat {
            iconSize + 140
        }
    }

    @Published var showSystemApps: Bool
    @Published var gridScale: GridScale

    private let defaults: UserDefaults
    fileprivate var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let showSystemApps = "preferences.showSystemApps"
        static let gridScale = "preferences.gridScale"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.showSystemApps) == nil {
            defaults.set(false, forKey: Keys.showSystemApps)
        }
        showSystemApps = defaults.bool(forKey: Keys.showSystemApps)

        let storedScale = defaults.integer(forKey: Keys.gridScale)
        gridScale = GridScale(rawValue: storedScale) ?? .comfortable

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
    }
}
