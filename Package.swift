// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FamilyTimer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FamilyTimerCore", targets: ["FamilyTimerCore"]),
        .executable(name: "familytimerd", targets: ["familytimerd"]),
    ],
    targets: [
        .target(name: "FamilyTimerCore"),
        .executableTarget(name: "familytimerd", dependencies: ["FamilyTimerCore"]),
        .testTarget(name: "FamilyTimerCoreTests", dependencies: ["FamilyTimerCore"]),
    ]
)
