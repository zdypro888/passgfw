// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PassGFW",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "PassGFW",
            targets: ["PassGFW"]),
    ],
    targets: [
        .target(
            name: "PassGFW",
            dependencies: []),
        .testTarget(
            name: "PassGFWTests",
            dependencies: ["PassGFW"]),
    ]
)

