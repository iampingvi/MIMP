// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MIMP",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "MIMP",
            targets: ["MIMP"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MIMP",
            dependencies: []),
        .testTarget(
            name: "MIMPTests",
            dependencies: ["MIMP"]),
    ]
) 