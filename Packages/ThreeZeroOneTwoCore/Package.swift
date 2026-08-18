// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreeZeroOneTwoCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ThreeZeroOneTwoCore", targets: ["ThreeZeroOneTwoCore"]),
        .executable(name: "3012-publisher", targets: ["ThreeZeroOneTwoPublisher"])
    ],
    targets: [
        .target(name: "ThreeZeroOneTwoCore"),
        .executableTarget(
            name: "ThreeZeroOneTwoPublisher",
            dependencies: ["ThreeZeroOneTwoCore"]
        ),
        .testTarget(
            name: "ThreeZeroOneTwoCoreTests",
            dependencies: ["ThreeZeroOneTwoCore"]
        )
    ]
)
