// swift-tools-version:6.0
import PackageDescription

// TokenUsage：监测 token plan 订阅余额的 macOS 菜单栏应用。
// 约定见 AGENTS.md：单一 executable target，不建 xcodeproj，最低 macOS 15。
let package = Package(
    name: "TokenUsage",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TokenUsage",
            path: "Sources/TokenUsage"
        ),
        .testTarget(
            name: "TokenUsageTests",
            dependencies: ["TokenUsage"],
            path: "Tests/TokenUsageTests"
        ),
    ]
)
