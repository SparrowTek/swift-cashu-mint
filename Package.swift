// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-cashu-mint",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "swift-cashu-mint",
            targets: ["swift-cashu-mint"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreCashu"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.15.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-cashu-mint",
            dependencies: [
                "CoreCashu",
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .testTarget(
            name: "swift-cashu-mintTests",
            dependencies: ["swift-cashu-mint"]
        ),
    ]
)
