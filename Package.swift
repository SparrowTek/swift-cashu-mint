// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-cashu-mint",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "swift-cashu-mint",
            targets: ["swift-cashu-mint"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "swift-cashu-mint"),
        .testTarget(
            name: "swift-cashu-mintTests",
            dependencies: ["swift-cashu-mint"]
        ),
    ]
)
