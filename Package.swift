// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-acp",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "ACP",
            targets: ["ACP"]
        ),
    ],
    targets: [
        .target(
            name: "ACP",
            path: "Sources/ACP"
        ),
        .testTarget(
            name: "ACPTests",
            dependencies: ["ACP"],
            path: "Tests/ACPTests"
        ),
    ]
)
