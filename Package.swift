// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapAI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SnapAILogic", targets: ["SnapAILogic"]),
        .executable(name: "SnapAI", targets: ["SnapAI"]),
        .executable(name: "SnapAIUpdater", targets: ["SnapAIUpdater"])
    ],
    dependencies: [
        // 更新通道:Sparkle 2(appcast + EdDSA 签名 + 原生更新安装)。
        // 这是仓库第一个第三方依赖,供应链扫描因此从「零依赖直接通过」
        // 变为真实扫描(osv-scanner),见 scripts/run-supply-chain-scan.sh。
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
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
                .linkedFramework("Vision"),
                .linkedFramework("NaturalLanguage"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SnapAI",
            dependencies: [
                "SnapAILogic",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SnapAI",
            resources: [.copy("Resources")],
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
