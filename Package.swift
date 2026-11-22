// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FamilyTimer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FamilyTimerCore", targets: ["FamilyTimerCore"]),
        .executable(name: "familytimerd", targets: ["familytimerd"]),
        .executable(name: "FamilyTimerAgent", targets: ["FamilyTimerAgent"]),
    ],
    targets: [
        .target(name: "FamilyTimerCore"),
        .executableTarget(name: "familytimerd", dependencies: ["FamilyTimerCore"]),
        .executableTarget(name: "FamilyTimerAgent", dependencies: ["FamilyTimerCore"]),
        .testTarget(name: "FamilyTimerCoreTests", dependencies: ["FamilyTimerCore"]),
    ]
)
