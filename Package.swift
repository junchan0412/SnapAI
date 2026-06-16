// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapAI",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SnapAI",
            path: "Sources/SnapAI",
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
