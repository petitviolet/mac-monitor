// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "MacMonitorCore",
            path: "Sources/MacMonitorCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "MacMonitor",
            dependencies: ["MacMonitorCore"],
            path: "Sources/MacMonitor",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MacMonitorCoreTests",
            dependencies: ["MacMonitorCore"],
            path: "Tests/MacMonitorCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
