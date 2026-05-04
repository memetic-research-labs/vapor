// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "vapor-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "VaporCLI",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/VaporCLI"
        ),
        .testTarget(
            name: "VaporCLITests",
            dependencies: ["VaporCLI"],
            path: "Tests/VaporCLITests"
        ),
    ]
)
