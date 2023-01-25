// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Junction",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "Junction", targets: ["Junction"]),
    ],
    targets: [
        .target(name: "Junction"),
        .testTarget(name: "JunctionTests", dependencies: ["Junction"]),
    ]
)
