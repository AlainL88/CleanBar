// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanBar",
    platforms: [
        .macOS(.v14)
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
    ]
)
