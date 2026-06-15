// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentDrop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentDropCore", targets: ["AgentDropCore"]),
        .executable(name: "agent-drop", targets: ["AgentDropCLI"])
    ],
    targets: [
        .target(
            name: "AgentDropCore",
            path: "Sources/AgentDropCore"
        ),
        .executableTarget(
            name: "AgentDropCLI",
            dependencies: ["AgentDropCore"],
            path: "Sources/AgentDropCLI"
        ),
        .testTarget(
            name: "AgentDropCoreTests",
            dependencies: ["AgentDropCore"],
            path: "Tests/AgentDropCoreTests"
        )
    ]
)
