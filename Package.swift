// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StartMyAppIndex",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StartMyAppIndex", targets: ["StartMyAppIndex"]),
        .executable(name: "application-index-benchmark", targets: ["ApplicationIndexBenchmark"]),
    ],
    targets: [
        .target(
            name: "StartMyAppIndex",
            path: "StartMyApp",
            exclude: [
                "AppState.swift", "Assets.xcassets", "ContentView.swift", "Extensions",
                "StartMyAppApp.swift", "Views",
                "Models/AppCollectionItem.swift", "Models/AppPreferences.swift",
                "Models/KeyboardShortcutPreference.swift", "Models/RecentLaunch.swift",
                "Services/AboutWindowController.swift", "Services/AppIconCache.swift",
                "Services/ApplicationDirectoryMonitor.swift", "Services/FavoritesStore.swift",
                "Services/GlobalShortcutCenter.swift", "Services/LayoutStore.swift",
                "Services/LearnWindowController.swift", "Services/RecentsStore.swift",
                "Services/SemanticSearchService.swift", "Services/ShortcutCoordinator.swift",
                "Services/StatusItemCoordinator.swift", "Services/WindowManager.swift",
            ],
            sources: [
                "Models/DiscoveredApp.swift",
                "Services/ApplicationDiscoveryService.swift",
            ]
        ),
        .executableTarget(
            name: "ApplicationIndexBenchmark",
            dependencies: ["StartMyAppIndex"],
            path: "Benchmarks/ApplicationIndexBenchmark"
        ),
        .testTarget(
            name: "StartMyAppIndexTests",
            dependencies: ["StartMyAppIndex"],
            path: "Tests/StartMyAppIndexTests"
        ),
    ]
)
