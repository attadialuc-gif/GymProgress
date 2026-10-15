import Foundation

/// Version of the persisted/exported data schema. Bump together with a SwiftData `VersionedSchema`
/// and an export migration.
public enum GymSchema {
    public static let currentVersion = 1
}
