import Foundation

/// How an exercise is measured.
public enum MeasurementType: String, Codable, Sendable, CaseIterable, Hashable {
    /// External load × repetitions (barbell, dumbbell, machine, cable...).
    case weightReps
    /// Body weight × repetitions, optionally with added weight or assistance.
    case bodyweightReps
    /// Time under tension / hold, in seconds.
    case duration
}

/// How the stored weight relates to the load actually moved.
public enum LoadMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// The stored weight is the total load (e.g. barbell with plates, machine stack).
    case total
    /// The stored weight is per side / per hand (dumbbells, unilateral work).
    case perSide
}

public enum Equipment: String, Codable, Sendable, CaseIterable, Hashable {
    case barbell
    case dumbbell
    case machine
    case cable
    case smithMachine
    case kettlebell
    case bodyweight
    case band
    case ezBar
    case other
}

public enum MuscleGroup: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case chest
    case upperBack
    case lats
    case traps
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case adductors
    case abductors
    case abs
    case obliques
    case lowerBack

    public static func < (lhs: MuscleGroup, rhs: MuscleGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Set type. Extensible: new kinds must declare whether they count as effective work and whether
/// they feed the progression engine.
public enum SetKind: String, Codable, Sendable, CaseIterable, Hashable {
    case warmup
    case working
    case dropSet

    /// Counts toward volume and effective-set statistics.
    public var countsAsEffectiveWork: Bool {
        switch self {
        case .warmup: false
        case .working, .dropSet: true
        }
    }

    /// Feeds the progression engine (only straight working sets are compared).
    public var feedsProgression: Bool {
        self == .working
    }
}

public enum SetStatus: String, Codable, Sendable, Hashable {
    case pending
    case completed
}

public enum SessionStatus: String, Codable, Sendable, Hashable {
    case active
    case paused
    case completed
    case discarded
}
