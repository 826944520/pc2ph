// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioRelayClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AudioRelayClient",
            targets: ["AudioRelayClient"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat.git", from: "0.53.0"),
    ],
    targets: [
        .target(
            name: "AudioRelayClient",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources",
            exclude: ["App/Info.plist"]
        )
    ]
)
