// swift-tools-version: 6.0
import PackageDescription

// GymCore: pure domain logic (no SwiftUI, no SwiftData). Builds and tests on macOS, iOS and Linux.
// GymStore: persistence-agnostic application layer (records, repository protocol, workout/routine
// services, JSON file store, export DTOs). Also platform-independent; the iOS app plugs a SwiftData
// implementation of `GymRepository` into the same services.
let package = Package(
    name: "GymCore",
    defaultLocalization: "es",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GymCore", targets: ["GymCore"]),
        .library(name: "GymStore", targets: ["GymStore"]),
    ],
    targets: [
        .target(name: "GymCore"),
        .target(name: "GymStore", dependencies: ["GymCore"]),
        .testTarget(name: "GymCoreTests", dependencies: ["GymCore"]),
        .testTarget(name: "GymStoreTests", dependencies: ["GymStore", "GymCore"]),
    ]
)
