// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreeZeroOneTwoCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "ThreeZeroOneTwoCore", targets: ["ThreeZeroOneTwoCore"])
    ],
    targets: [
        .target(name: "ThreeZeroOneTwoCore"),
        .testTarget(
            name: "ThreeZeroOneTwoCoreTests",
            dependencies: ["ThreeZeroOneTwoCore"]
        )
    ]
)
