// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BlurApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BlurApp", targets: ["BlurApp"])
    ],
    targets: [
        .executableTarget(
            name: "BlurApp",
            path: "Sources/BlurApp",
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "BlurAppTests",
            dependencies: ["BlurApp"],
            path: "Tests/BlurAppTests"
        )
    ]
)
