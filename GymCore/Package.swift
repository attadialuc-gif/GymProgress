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
    // One dynamic framework with both modules: the iOS app and its test bundle share a single
    // copy (no duplicated types or resource bundles). Two dynamic products would each embed
    // GymCore, which Xcode rejects.
    products: [
        .library(name: "GymKit", type: .dynamic, targets: ["GymCore", "GymStore"]),
    ],
    targets: [
        .target(name: "GymCore"),
        .target(name: "GymStore", dependencies: ["GymCore"], resources: [.process("Resources")]),
        // Cross-platform fidelity: serializes inputs/outputs of the existing cases as golden JSON
        // fixtures (crossplatform/fixtures) and verifies imports of exports made by other ports.
        // Not part of the app; it only calls the public API.
        .executableTarget(name: "FixtureExporter", dependencies: ["GymCore", "GymStore"]),
        .testTarget(name: "GymCoreTests", dependencies: ["GymCore"]),
        .testTarget(name: "GymStoreTests", dependencies: ["GymStore", "GymCore"]),
    ]
)
