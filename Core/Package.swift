// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LaunchDeckCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchDeckCore", targets: ["LaunchDeckCore"]),
        .executable(name: "application-index-benchmark", targets: ["ApplicationIndexBenchmark"]),
    ],
    targets: [
        .target(name: "LaunchDeckCore"),
        .executableTarget(
            name: "ApplicationIndexBenchmark",
            dependencies: ["LaunchDeckCore"]
        ),
        .testTarget(
            name: "LaunchDeckCoreTests",
            dependencies: ["LaunchDeckCore"]
        ),
    ]
)
