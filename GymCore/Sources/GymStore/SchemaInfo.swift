import Foundation

/// Version of the persisted/exported data schema. Bump together with a SwiftData `VersionedSchema`
/// and an export migration.
public enum GymSchema {
    public static let currentVersion = 1
}

extension DateInterval {
    /// [start, end): periods never count an instant twice at their boundary.
    public func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
