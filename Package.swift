// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapAI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SnapAILogic", targets: ["SnapAILogic"]),
        .executable(name: "SnapAI", targets: ["SnapAI"]),
        .executable(name: "SnapAIUpdater", targets: ["SnapAIUpdater"])
    ],
    targets: [
        .target(
            name: "SnapAILogic",
            path: "Sources/SnapAILogic",
            packageAccess: true,
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SnapAI",
            dependencies: ["SnapAILogic"],
            path: "Sources/SnapAI",
            packageAccess: true,
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SnapAIUpdater",
            path: "Sources/SnapAIUpdater"
        ),
        .testTarget(
            name: "SnapAILogicTests",
            dependencies: ["SnapAILogic"],
            path: "Tests/SnapAILogicTests",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
