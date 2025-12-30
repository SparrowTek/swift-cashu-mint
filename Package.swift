// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-cashu-mint",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "swift-cashu-mint", targets: ["swift-cashu-mint"])
    ],
    dependencies: [
        .package(path: "../CoreCashu"),
        // Pin to 2.17.0 to avoid swift-configuration compiler crash in Swift 6.2.3
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.17.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-cashu-mint",
            dependencies: [
                "CoreCashu",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "swift-cashu-mintTests",
            dependencies: [
                "swift-cashu-mint",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
