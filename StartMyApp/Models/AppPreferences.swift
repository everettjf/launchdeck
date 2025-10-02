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
    @Published var showRecentApps: Bool
    @Published var showMenuBarIcon: Bool
    @Published var isGlobalShortcutEnabled: Bool
    @Published var globalShortcut: KeyboardShortcutPreference

    private let defaults: UserDefaults
    fileprivate var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let showSystemApps = "preferences.showSystemApps"
        static let gridScale = "preferences.gridScale"
        static let sortOption = "preferences.sortOption"
        static let showRecentApps = "preferences.showRecentApps"
        static let showMenuBarIcon = "preferences.showMenuBarIcon"
        static let globalShortcutEnabled = "preferences.globalShortcutEnabled"
        static let globalShortcut = "preferences.globalShortcut"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.showSystemApps) == nil {
            defaults.set(true, forKey: Keys.showSystemApps)
        }
        showSystemApps = defaults.object(forKey: Keys.showSystemApps).map { _ in defaults.bool(forKey: Keys.showSystemApps) } ?? true

        let storedScale = defaults.integer(forKey: Keys.gridScale)
        gridScale = GridScale(rawValue: storedScale) ?? .comfortable

        let storedSort = defaults.integer(forKey: Keys.sortOption)
        sortOption = SortOption(rawValue: storedSort) ?? .custom

        if defaults.object(forKey: Keys.showRecentApps) == nil {
            defaults.set(true, forKey: Keys.showRecentApps)
        }
        showRecentApps = defaults.object(forKey: Keys.showRecentApps).map { _ in defaults.bool(forKey: Keys.showRecentApps) } ?? true

        if defaults.object(forKey: Keys.showMenuBarIcon) == nil {
            defaults.set(true, forKey: Keys.showMenuBarIcon)
        }
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)

        if defaults.object(forKey: Keys.globalShortcutEnabled) == nil {
            defaults.set(true, forKey: Keys.globalShortcutEnabled)
        }
        isGlobalShortcutEnabled = defaults.bool(forKey: Keys.globalShortcutEnabled)

        if let shortcutData = defaults.data(forKey: Keys.globalShortcut),
           let decoded = try? JSONDecoder().decode(KeyboardShortcutPreference.self, from: shortcutData) {
            globalShortcut = decoded
        } else {
            globalShortcut = .default
            if let data = try? JSONEncoder().encode(globalShortcut) {
                defaults.set(data, forKey: Keys.globalShortcut)
            }
        }

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

        $showRecentApps
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.showRecentApps)
            }
            .store(in: &cancellables)

        $showMenuBarIcon
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.showMenuBarIcon)
            }
            .store(in: &cancellables)

        $isGlobalShortcutEnabled
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.globalShortcutEnabled)
            }
            .store(in: &cancellables)

        $globalShortcut
            .dropFirst()
            .sink { [weak self] value in
                guard let data = try? JSONEncoder().encode(value) else { return }
                self?.defaults.set(data, forKey: Keys.globalShortcut)
            }
            .store(in: &cancellables)
    }
}
