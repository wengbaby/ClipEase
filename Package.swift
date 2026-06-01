// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClipEase",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClipEase",
            path: "Sources/ClipEase"
        ),
        .testTarget(
            name: "ClipEaseTests",
            dependencies: ["ClipEase"],
            path: "Tests/ClipEaseTests"
        ),
    ]
)
