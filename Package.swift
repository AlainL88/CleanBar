// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanBar",
    platforms: [
        .macOS("26.5")
    ],
    products: [
        .library(
            name: "CleanBar",
            targets: ["CleanBar"]
        )
    ],
    targets: [
        .target(
            name: "CleanBar",
            path: "CleanBar",
            exclude: ["CleanBarApp.swift"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "CleanBarTests",
            dependencies: ["CleanBar"],
            path: "CleanBarTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
