import Foundation

/// Identifies a progression strategy. New strategies add a case here and a type conforming to
/// `ProgressionStrategy`; the UI only consumes `Recommendation`, so it does not change.
public enum ProgressionStrategyKind: String, Codable, Sendable, CaseIterable, Hashable {
    case doubleProgression
}

/// Per-exercise progression criteria (overridable per routine exercise). Every field is editable
/// by the user. Changing a config never rewrites past sessions: logs keep their own snapshot.
public struct ProgressionConfig: Codable, Sendable, Hashable {
    public var strategy: ProgressionStrategyKind
    /// Number of working sets the user aims for.
    public var targetSets: Int
    /// Rep range (for `duration` exercises see `secondsMin` / `secondsMax`).
    public var repMin: Int
    public var repMax: Int
    /// Target reps in reserve. `nil` = no effort target configured.
    public var targetRIR: Int?
    /// Starting load set by the user when there is no comparable history. Never invented.
    public var initialWeight: Double?
    /// Load increment in kg (per side when the exercise is `perSide`).
    public var increment: Double
    /// Discrete loads actually available (dumbbell rack, machine stack). When non-empty, it wins
    /// over `increment` to pick the next load.
    public var availableWeights: [Double]?
    /// Consecutive comparable sessions at the top of the range required before increasing load.
    public var requiredConsecutiveSessions: Int
    /// Days without a comparable session after which the engine suggests reassessing instead of
    /// increasing.
    public var reassessAfterDays: Int
    /// Duration exercises: target range and step, in seconds.
    public var secondsMin: Int
    public var secondsMax: Int
    public var secondsIncrement: Int

    public init(
        strategy: ProgressionStrategyKind = .doubleProgression,
        targetSets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        targetRIR: Int? = 2,
        initialWeight: Double? = nil,
        increment: Double = 2.5,
        availableWeights: [Double]? = nil,
        requiredConsecutiveSessions: Int = 1,
        reassessAfterDays: Int = 21,
        secondsMin: Int = 30,
        secondsMax: Int = 60,
        secondsIncrement: Int = 5
    ) {
        self.strategy = strategy
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.targetRIR = targetRIR
        self.initialWeight = initialWeight
        self.increment = increment
        self.availableWeights = availableWeights
        self.requiredConsecutiveSessions = requiredConsecutiveSessions
        self.reassessAfterDays = reassessAfterDays
        self.secondsMin = secondsMin
        self.secondsMax = secondsMax
        self.secondsIncrement = secondsIncrement
    }

    public static let `default` = ProgressionConfig()

    /// Returns a copy with values clamped to sane bounds so the engine never divides by zero or
    /// loops on inverted ranges. Out-of-range user input is corrected, not rejected.
    public func sanitized() -> ProgressionConfig {
        var copy = self
        copy.targetSets = max(1, min(targetSets, 20))
        copy.repMin = max(1, min(repMin, 100))
        copy.repMax = max(copy.repMin, min(repMax, 100))
        if let rir = targetRIR { copy.targetRIR = max(0, min(rir, 10)) }
        if let w = initialWeight, !w.isFinite || w < 0 { copy.initialWeight = nil }
        copy.increment = (increment.isFinite && increment > 0) ? increment : 2.5
        copy.availableWeights = availableWeights.map { list in
            Array(Set(list.filter { $0.isFinite && $0 >= 0 }.map(LoadMath.normalized))).sorted()
        }
        if copy.availableWeights?.isEmpty == true { copy.availableWeights = nil }
        copy.requiredConsecutiveSessions = max(1, min(requiredConsecutiveSessions, 10))
        copy.reassessAfterDays = max(1, reassessAfterDays)
        copy.secondsMin = max(1, secondsMin)
        copy.secondsMax = max(copy.secondsMin, secondsMax)
        copy.secondsIncrement = max(1, secondsIncrement)
        return copy
    }
}
