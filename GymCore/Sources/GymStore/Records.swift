import Foundation
import GymCore

// Persistable records, independent of the storage technology. The SwiftData models in the app map
// 1:1 to these structs. Catalog/templates are editable; history (sessions, logs, sets, decisions)
// keeps snapshots so later catalog edits never alter it.

public struct RoutineTemplate: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var notes: String
    public var isArchived: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0, notes: String = "", isArchived: Bool = false, createdAt: Date) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

public struct RoutineExercise: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var routineId: UUID
    public var exerciseId: UUID
    public var sortOrder: Int
    /// Exercises sharing a group number are performed as a superset / biset.
    public var supersetGroup: Int?
    public var restSeconds: Int?
    public var notes: String
    /// Per-routine override of the exercise's progression criteria (sets, range, RIR, increment…).
    public var progressionOverride: ProgressionConfig?

    public init(id: UUID = UUID(), routineId: UUID, exerciseId: UUID, sortOrder: Int, supersetGroup: Int? = nil, restSeconds: Int? = nil, notes: String = "", progressionOverride: ProgressionConfig? = nil) {
        self.id = id
        self.routineId = routineId
        self.exerciseId = exerciseId
        self.sortOrder = sortOrder
        self.supersetGroup = supersetGroup
        self.restSeconds = restSeconds
        self.notes = notes
        self.progressionOverride = progressionOverride
    }
}

public struct PauseInterval: Codable, Sendable, Hashable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

public struct WorkoutSession: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var routineId: UUID?
    /// Routine name at the time of the session (history never depends on the template).
    public var routineNameSnapshot: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var pauses: [PauseInterval]
    public var status: SessionStatus
    public var notes: String
    /// Illness, deload, travel…: shown, but excluded from trends and recommendations.
    public var isAtypical: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), routineId: UUID?, routineNameSnapshot: String?, startedAt: Date, endedAt: Date? = nil, pauses: [PauseInterval] = [], status: SessionStatus = .active, notes: String = "", isAtypical: Bool = false, updatedAt: Date) {
        self.id = id
        self.routineId = routineId
        self.routineNameSnapshot = routineNameSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pauses = pauses
        self.status = status
        self.notes = notes
        self.isAtypical = isAtypical
        self.updatedAt = updatedAt
    }

    /// Elapsed training time, excluding pauses. Timestamp-based: survives app suspension.
    public func elapsed(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        let paused = pauses.reduce(0.0) { acc, p in
            let pEnd = min(p.end ?? end, end)
            return acc + max(0, pEnd.timeIntervalSince(p.start))
        }
        return max(0, end.timeIntervalSince(startedAt) - paused)
    }

    public var isOpen: Bool { status == .active || status == .paused }
}

/// One exercise inside a session. Holds snapshots, the comparability context and the recommendation
/// frozen when the exercise was first opened (audit of what was shown).
public struct ExerciseLog: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var sessionId: UUID
    public var exerciseId: UUID
    public var routineExerciseId: UUID?
    /// Superset / biset group copied from the routine (exercises with the same group alternate;
    /// rest starts after the last exercise of the round). Optional in stored data (schema v1).
    public var supersetGroup: Int? = nil
    public var snapshot: ExerciseSnapshot
    /// Effective progression config at session start (routine override ?? exercise config).
    public var configSnapshot: ProgressionConfig
    public var variantLabel: String?
    public var equipmentLabel: String?
    /// Planned position in the session (editable for this session only).
    public var plannedOrder: Int
    /// Real execution order: assigned when the first set of this exercise is completed.
    public var executionOrder: Int?
    public var restSeconds: Int?
    public var notes: String
    public var isAtypical: Bool
    public var frozenRecommendation: Recommendation?
    public var recommendationFrozenAt: Date?

    public init(id: UUID = UUID(), sessionId: UUID, exerciseId: UUID, routineExerciseId: UUID? = nil, snapshot: ExerciseSnapshot, configSnapshot: ProgressionConfig, variantLabel: String? = nil, equipmentLabel: String? = nil, plannedOrder: Int, executionOrder: Int? = nil, restSeconds: Int? = nil, notes: String = "", isAtypical: Bool = false, frozenRecommendation: Recommendation? = nil, recommendationFrozenAt: Date? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.routineExerciseId = routineExerciseId
        self.snapshot = snapshot
        self.configSnapshot = configSnapshot
        self.variantLabel = variantLabel
        self.equipmentLabel = equipmentLabel
        self.plannedOrder = plannedOrder
        self.executionOrder = executionOrder
        self.restSeconds = restSeconds
        self.notes = notes
        self.isAtypical = isAtypical
        self.frozenRecommendation = frozenRecommendation
        self.recommendationFrozenAt = recommendationFrozenAt
    }

    public var context: ComparabilityContext {
        ComparabilityContext(exerciseId: exerciseId, variantLabel: variantLabel, equipmentLabel: equipmentLabel, loadMode: snapshot.loadMode)
    }
}

public struct SetLog: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var exerciseLogId: UUID
    public var index: Int
    public var kind: SetKind
    public var status: SetStatus
    public var weight: Double?
    public var reps: Int?
    public var seconds: Int?
    public var addedWeight: Double?
    public var assistance: Double?
    public var rir: Double?
    public var rpe: Double?
    public var completedAt: Date?
    public var excludedFromEstimates: Bool
    /// Reference shown next to the input (from an accepted/modified recommendation or copied loads).
    public var targetReps: Int?
    public var targetSeconds: Int?

    public init(id: UUID = UUID(), exerciseLogId: UUID, index: Int, kind: SetKind = .working, status: SetStatus = .pending, weight: Double? = nil, reps: Int? = nil, seconds: Int? = nil, addedWeight: Double? = nil, assistance: Double? = nil, rir: Double? = nil, rpe: Double? = nil, completedAt: Date? = nil, excludedFromEstimates: Bool = false, targetReps: Int? = nil, targetSeconds: Int? = nil) {
        self.id = id
        self.exerciseLogId = exerciseLogId
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
        self.targetReps = targetReps
        self.targetSeconds = targetSeconds
    }

    public var performed: PerformedSet {
        PerformedSet(index: index, kind: kind, status: status, weight: weight, reps: reps, seconds: seconds, addedWeight: addedWeight, assistance: assistance, rir: rir, rpe: rpe, completedAt: completedAt, excludedFromEstimates: excludedFromEstimates)
    }
}

public enum DecisionKind: String, Codable, Sendable, Hashable {
    case accepted
    case modified
    case ignored
}

/// The recommendation as shown to the user (kept inside the decision for audit).
public struct RecommendationSnapshot: Codable, Sendable, Hashable {
    public var action: RecommendationAction
    public var reason: RecommendationReason
    public var confidence: RecommendationConfidence
    public var targetWeight: Double?
    public var targetReps: [Int]
    public var targetSeconds: [Int]?
    public var reasonText: String

    public init(_ r: Recommendation) {
        action = r.action
        reason = r.reason
        confidence = r.confidence
        targetWeight = r.targetWeight
        targetReps = r.targetReps
        targetSeconds = r.targetSeconds
        reasonText = r.reasonText
    }
}

/// What the user chose. Source of truth for "today's target"; the engine never overwrites it.
public struct RecommendationDecision: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var exerciseLogId: UUID
    public var recommended: RecommendationSnapshot
    public var kind: DecisionKind
    public var finalWeight: Double?
    public var finalReps: [Int]
    public var finalSeconds: [Int]?
    public var decidedAt: Date

    public init(id: UUID = UUID(), exerciseLogId: UUID, recommended: RecommendationSnapshot, kind: DecisionKind, finalWeight: Double?, finalReps: [Int], finalSeconds: [Int]?, decidedAt: Date) {
        self.id = id
        self.exerciseLogId = exerciseLogId
        self.recommended = recommended
        self.kind = kind
        self.finalWeight = finalWeight
        self.finalReps = finalReps
        self.finalSeconds = finalSeconds
        self.decidedAt = decidedAt
    }
}

public enum GoalMetric: String, Codable, Sendable, Hashable, CaseIterable {
    case weight
    case repsAtWeight
    case estimatedOneRepMax
    case sessionVolume
}

public enum GoalStatus: String, Codable, Sendable, Hashable {
    case active
    case achieved
    case abandoned
}

public struct Goal: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var exerciseId: UUID
    public var metric: GoalMetric
    public var value: Double
    /// For `repsAtWeight`: the load.
    public var weight: Double?
    public var targetDate: Date?
    public var status: GoalStatus
    public var createdAt: Date
    public var achievedAt: Date?

    public init(id: UUID = UUID(), exerciseId: UUID, metric: GoalMetric, value: Double, weight: Double? = nil, targetDate: Date? = nil, status: GoalStatus = .active, createdAt: Date, achievedAt: Date? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.metric = metric
        self.value = value
        self.weight = weight
        self.targetDate = targetDate
        self.status = status
        self.createdAt = createdAt
        self.achievedAt = achievedAt
    }
}

public enum WeightUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case kg
    case lb
}

public enum AppTheme: String, Codable, Sendable, Hashable, CaseIterable {
    case dark
    case light
    case system
}

public struct UserSettings: Codable, Sendable, Hashable {
    /// Presentation only: data is always stored in kg.
    public var weightUnit: WeightUnit
    /// 1 = Sunday … 7 = Saturday. Default Monday.
    public var firstWeekday: Int
    public var defaultRestSeconds: Int
    public var theme: AppTheme
    public var weeklyGoal: Int
    public var streakMode: StreakMode
    public var maxGapDays: Int
    public var indirectSetFactor: Double
    public var oneRepMax: OneRepMaxSettings
    public var minSetsForValidSession: Int
    public var keepScreenOn: Bool
    public var restNotifications: Bool
    /// Optional: enables body-weight volume. `nil` = unknown (never invented).
    public var bodyweightKg: Double?

    public init(weightUnit: WeightUnit = .kg, firstWeekday: Int = 2, defaultRestSeconds: Int = 120, theme: AppTheme = .dark, weeklyGoal: Int = 3, streakMode: StreakMode = .weeklyPlan, maxGapDays: Int = 2, indirectSetFactor: Double = 0.5, oneRepMax: OneRepMaxSettings = .default, minSetsForValidSession: Int = 3, keepScreenOn: Bool = true, restNotifications: Bool = true, bodyweightKg: Double? = nil) {
        self.weightUnit = weightUnit
        self.firstWeekday = firstWeekday
        self.defaultRestSeconds = defaultRestSeconds
        self.theme = theme
        self.weeklyGoal = weeklyGoal
        self.streakMode = streakMode
        self.maxGapDays = maxGapDays
        self.indirectSetFactor = indirectSetFactor
        self.oneRepMax = oneRepMax
        self.minSetsForValidSession = minSetsForValidSession
        self.keepScreenOn = keepScreenOn
        self.restNotifications = restNotifications
        self.bodyweightKg = bodyweightKg
    }

    public static let `default` = UserSettings()
}

/// Whole database as one Codable document. Used by the JSON store, export/import and backups.
/// Decoupled from SwiftData models.
public struct GymDatabase: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var exportedAt: Date?
    public var exercises: [Exercise]
    public var routines: [RoutineTemplate]
    public var routineExercises: [RoutineExercise]
    public var schedule: [ScheduleEntry]
    public var sessions: [WorkoutSession]
    public var exerciseLogs: [ExerciseLog]
    public var setLogs: [SetLog]
    public var decisions: [RecommendationDecision]
    public var comparabilityLinks: [ComparabilityLink]
    public var goals: [Goal]
    public var settings: UserSettings

    public init(schemaVersion: Int = GymSchema.currentVersion, exportedAt: Date? = nil, exercises: [Exercise] = [], routines: [RoutineTemplate] = [], routineExercises: [RoutineExercise] = [], schedule: [ScheduleEntry] = [], sessions: [WorkoutSession] = [], exerciseLogs: [ExerciseLog] = [], setLogs: [SetLog] = [], decisions: [RecommendationDecision] = [], comparabilityLinks: [ComparabilityLink] = [], goals: [Goal] = [], settings: UserSettings = .default) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.exercises = exercises
        self.routines = routines
        self.routineExercises = routineExercises
        self.schedule = schedule
        self.sessions = sessions
        self.exerciseLogs = exerciseLogs
        self.setLogs = setLogs
        self.decisions = decisions
        self.comparabilityLinks = comparabilityLinks
        self.goals = goals
        self.settings = settings
    }
}

public enum GymStoreError: Error, Equatable, Sendable {
    case notFound(String)
    case sessionAlreadyOpen
    case sessionNotOpen
    case hasHistory
    case hasCompletedSets
    case missingValues
    case invalidValue(String)
    case unsupportedSchemaVersion(Int)
    case invalidImport(String)
    case storage(String)
}
