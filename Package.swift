// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PanePilot",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "PanePilotKit",
            targets: ["PanePilotKit"]
        ),
        .executable(
            name: "PanePilot",
            targets: ["PanePilot"]
        ),
    ],
    targets: [
        .target(
            name: "PanePilotKit"
        ),
        .executableTarget(
            name: "PanePilot",
            dependencies: ["PanePilotKit"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "PanePilotKitTests",
            dependencies: ["PanePilotKit"]
        ),
    ]
)
