import Foundation

public enum RecommendationAction: String, Codable, Sendable, Hashable {
    /// No comparable history. `targetWeight` is only set when the user configured an initial target.
    case needsInitialTarget
    case increaseWeight
    /// Same load, more reps (or more seconds for duration exercises).
    case increaseReps
    case maintain
    /// Review rest, sleep, technique and load. Reducing load is an option the user decides.
    case reassess
}

public enum RecommendationConfidence: String, Codable, Sendable, Hashable {
    case high
    /// Effort data (RIR/RPE) was not recorded: the suggestion only holds under the listed conditions.
    case conditional
}

/// Machine-readable reason. The UI may localize from this code; `reasonText` carries the
/// engine's own Spanish text.
public enum RecommendationReason: String, Codable, Sendable, Hashable {
    case noComparableHistory
    case noComparableHistoryInContext
    case initialTarget
    case longBreak
    case incompleteSets
    case topOfRangeReached
    case topOfRangeNoHeavierLoad
    case topOfRangeNeedsConfirmation
    case effortAboveTarget
    case repeatedBelowRepMin
    case performanceDropped
    case belowRepMin
    case belowTopOfRange
    case repsHeldByEffort
    case durationTopReached
}

public enum TrendClassification: String, Codable, Sendable, Hashable {
    /// Fewer than the minimum comparable sessions: no conclusion is drawn.
    case insufficientData
    case progressing
    case stable
    case possiblePlateau
    case declining
}

/// Today's target as configured (shown next to the recommendation).
public struct SessionTarget: Codable, Sendable, Hashable {
    public var sets: Int
    public var repMin: Int
    public var repMax: Int
    public var targetRIR: Int?
    public var secondsMin: Int
    public var secondsMax: Int

    public init(config: ProgressionConfig) {
        sets = config.targetSets
        repMin = config.repMin
        repMax = config.repMax
        targetRIR = config.targetRIR
        secondsMin = config.secondsMin
        secondsMax = config.secondsMax
    }
}

/// Compact view of one past performance, used for "última sesión" and the evidence list.
public struct PerformanceSummary: Codable, Sendable, Hashable {
    public struct SetSummary: Codable, Sendable, Hashable {
        public var load: Double
        /// Reps, or seconds for duration exercises.
        public var amount: Int
        public var rir: Double?
    }

    public var sessionId: UUID
    public var exerciseLogId: UUID
    public var date: Date
    public var context: ComparabilityContext
    public var measurement: MeasurementType
    /// Most frequent load among the progression sets (ties → heavier).
    public var workingLoad: Double
    /// Progression sets in execution order.
    public var sets: [SetSummary]

    public var amounts: [Int] { sets.map(\.amount) }
}

/// Output of the progression engine. Pure value: deterministic for a given input.
public struct Recommendation: Codable, Sendable, Hashable {
    public var strategy: ProgressionStrategyKind
    public var action: RecommendationAction
    public var reason: RecommendationReason
    public var confidence: RecommendationConfidence
    public var measurement: MeasurementType
    /// Target load (external kg; for body-weight work the net added load, negative = assistance;
    /// per side when the context is `perSide`).
    public var targetWeight: Double?
    /// Target reps per set (empty for duration exercises).
    public var targetReps: [Int]
    /// Target seconds per set (duration exercises only).
    public var targetSeconds: [Int]?
    public var target: SessionTarget
    /// Short Spanish explanation (1–2 lines).
    public var reasonText: String
    /// Conditions under which a `conditional` suggestion holds.
    public var conditions: [String]
    /// Extra notices (no heavier weight available, plateau, etc.).
    public var notes: [String]
    public var context: ComparabilityContext
    /// Last comparable performance (what the user did last time).
    public var lastPerformance: PerformanceSummary?
    /// Comparable performances used as evidence, most recent first (at most 5).
    public var evidence: [PerformanceSummary]
    /// Last performance in a *different* context, shown only as a "no equivalente" reference.
    public var nonEquivalentReference: PerformanceSummary?
    public var trend: TrendClassification
    public var generatedAt: Date

    public var evidenceSessionIds: [UUID] { evidence.map(\.sessionId) }
}
