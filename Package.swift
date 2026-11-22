// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FamilyTimer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FamilyTimerCore", targets: ["FamilyTimerCore"]),
    ],
    targets: [
        .target(name: "FamilyTimerCore"),
        .testTarget(name: "FamilyTimerCoreTests", dependencies: ["FamilyTimerCore"]),
    ]
)
