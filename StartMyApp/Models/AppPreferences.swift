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
