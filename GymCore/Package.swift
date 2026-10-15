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
    // Dynamic: the iOS app and its test bundle share ONE copy of each module (no duplicated
    // types or resource bundles when tests link the packages too).
    products: [
        .library(name: "GymCore", type: .dynamic, targets: ["GymCore"]),
        .library(name: "GymStore", type: .dynamic, targets: ["GymStore"]),
    ],
    targets: [
        .target(name: "GymCore"),
        .target(name: "GymStore", dependencies: ["GymCore"], resources: [.process("Resources")]),
        .testTarget(name: "GymCoreTests", dependencies: ["GymCore"]),
        .testTarget(name: "GymStoreTests", dependencies: ["GymStore", "GymCore"]),
    ]
)
