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
        .executable(
            name: "PassGFWExample",
            targets: ["PassGFWExample"])
    ],
    targets: [
        .target(
            name: "PassGFW",
            dependencies: []),
        .executableTarget(
            name: "PassGFWExample",
            dependencies: ["PassGFW"],
            path: "Examples",
            exclude: ["example_ios.swift"],
            sources: ["example_macos.swift"])
    ]
)

