import Foundation

/// One recorded set, as consumed by the calculators. Mirrors `SetLog` without persistence concerns.
public struct PerformedSet: Codable, Sendable, Hashable {
    public var index: Int
    public var kind: SetKind
    public var status: SetStatus
    /// External load in kg (per side when the log's load mode is `perSide`).
    public var weight: Double?
    public var reps: Int?
    public var seconds: Int?
    /// Body-weight exercises: extra load (belt, vest).
    public var addedWeight: Double?
    /// Body-weight exercises: assistance (band, assisted machine).
    public var assistance: Double?
    public var rir: Double?
    public var rpe: Double?
    public var completedAt: Date?
    /// User excluded this set from 1RM estimates.
    public var excludedFromEstimates: Bool

    public init(
        index: Int,
        kind: SetKind = .working,
        status: SetStatus = .completed,
        weight: Double? = nil,
        reps: Int? = nil,
        seconds: Int? = nil,
        addedWeight: Double? = nil,
        assistance: Double? = nil,
        rir: Double? = nil,
        rpe: Double? = nil,
        completedAt: Date? = nil,
        excludedFromEstimates: Bool = false
    ) {
        self.index = index
        self.kind = kind
        self.status = status
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
        self.addedWeight = addedWeight
        self.assistance = assistance
        self.rir = rir
        self.rpe = rpe
        self.completedAt = completedAt
        self.excludedFromEstimates = excludedFromEstimates
    }

    /// Reps in reserve: recorded RIR, or derived from RPE (RIR = 10 − RPE) when only RPE exists.
    public var effectiveRIR: Double? {
        if let rir { return rir }
        if let rpe { return max(0, 10 - rpe) }
        return nil
    }

    /// Net extra load for body-weight work: added − assistance (negative = assisted).
    public var netAddedLoad: Double {
        (addedWeight ?? 0) - (assistance ?? 0)
    }

    /// The load that progression compares, by measurement type.
    public func progressionLoad(for measurement: MeasurementType) -> Double {
        switch measurement {
        case .weightReps: weight ?? 0
        case .bodyweightReps: netAddedLoad
        case .duration: weight ?? 0
        }
    }

    /// Completed, with valid values for the measurement type. Pending sets are never effective
    /// (and never read as zero).
    public func isValidCompleted(for measurement: MeasurementType) -> Bool {
        guard status == .completed else { return false }
        switch measurement {
        case .weightReps:
            guard let weight, weight.isFinite, weight >= 0, let reps, reps >= 1 else { return false }
            return true
        case .bodyweightReps:
            guard let reps, reps >= 1 else { return false }
            if let a = addedWeight, !(a.isFinite && a >= 0) { return false }
            if let a = assistance, !(a.isFinite && a >= 0) { return false }
            return true
        case .duration:
            guard let seconds, seconds >= 1 else { return false }
            if let weight, !(weight.isFinite && weight >= 0) { return false }
            return true
        }
    }

    /// Effective set (section 8.1): effective-work kind, completed, valid values.
    public func isEffective(for measurement: MeasurementType) -> Bool {
        kind.countsAsEffectiveWork && isValidCompleted(for: measurement)
    }

    /// Set considered by the progression engine: straight working set, completed, valid.
    public func feedsProgression(for measurement: MeasurementType) -> Bool {
        kind.feedsProgression && isValidCompleted(for: measurement)
    }

    /// Progression "amount" of a set: reps, or seconds for duration exercises.
    public func amount(for measurement: MeasurementType) -> Int {
        switch measurement {
        case .weightReps, .bodyweightReps: reps ?? 0
        case .duration: seconds ?? 0
        }
    }
}

/// All sets of one exercise within one session, plus the context needed to compare it.
public struct ExercisePerformance: Codable, Sendable, Hashable {
    public var sessionId: UUID
    public var exerciseLogId: UUID
    public var sessionStart: Date
    public var sessionStatus: SessionStatus
    /// Session or exercise flagged as atypical (illness, deload, travel): shown, but excluded from
    /// trends and recommendations.
    public var isAtypical: Bool
    public var context: ComparabilityContext
    public var measurement: MeasurementType
    public var sets: [PerformedSet]

    public init(
        sessionId: UUID,
        exerciseLogId: UUID,
        sessionStart: Date,
        sessionStatus: SessionStatus = .completed,
        isAtypical: Bool = false,
        context: ComparabilityContext,
        measurement: MeasurementType = .weightReps,
        sets: [PerformedSet]
    ) {
        self.sessionId = sessionId
        self.exerciseLogId = exerciseLogId
        self.sessionStart = sessionStart
        self.sessionStatus = sessionStatus
        self.isAtypical = isAtypical
        self.context = context
        self.measurement = measurement
        self.sets = sets
    }

    public var effectiveSets: [PerformedSet] {
        sets.filter { $0.isEffective(for: measurement) }.sorted { $0.index < $1.index }
    }

    public var progressionSets: [PerformedSet] {
        sets.filter { $0.feedsProgression(for: measurement) }.sorted { $0.index < $1.index }
    }
}
