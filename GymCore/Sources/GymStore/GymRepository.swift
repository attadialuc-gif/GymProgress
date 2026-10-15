import Foundation
import GymCore

/// Storage abstraction. Services depend only on this protocol; the app plugs in SwiftData, tests use
/// `JSONGymRepository` (in memory or file-backed, to verify reloads).
/// Every mutating call persists immediately (incremental save: a crash never loses a completed set).
@MainActor
public protocol GymRepository: AnyObject {
    // Catalog
    func exercises() -> [Exercise]
    func exercise(id: UUID) -> Exercise?
    func upsertExercise(_ exercise: Exercise) throws
    func deleteExercise(id: UUID) throws

    // Routines
    func routines() -> [RoutineTemplate]
    func routine(id: UUID) -> RoutineTemplate?
    func upsertRoutine(_ routine: RoutineTemplate) throws
    func deleteRoutine(id: UUID) throws
    func routineExercises(routineId: UUID) -> [RoutineExercise]
    func routineExercise(id: UUID) -> RoutineExercise?
    func upsertRoutineExercise(_ item: RoutineExercise) throws
    func deleteRoutineExercise(id: UUID) throws

    // Schedule (append-only)
    func scheduleEntries() -> [ScheduleEntry]
    func insertScheduleEntry(_ entry: ScheduleEntry) throws

    // History
    func sessions() -> [WorkoutSession]
    func session(id: UUID) -> WorkoutSession?
    func upsertSession(_ session: WorkoutSession) throws
    func exerciseLogs(sessionId: UUID) -> [ExerciseLog]
    func exerciseLogs(exerciseId: UUID) -> [ExerciseLog]
    func exerciseLog(id: UUID) -> ExerciseLog?
    func upsertExerciseLog(_ log: ExerciseLog) throws
    func deleteExerciseLog(id: UUID) throws
    func setLogs(exerciseLogId: UUID) -> [SetLog]
    func setLog(id: UUID) -> SetLog?
    func upsertSetLog(_ set: SetLog) throws
    func deleteSetLog(id: UUID) throws
    func decision(exerciseLogId: UUID) -> RecommendationDecision?
    func upsertDecision(_ decision: RecommendationDecision) throws

    // Comparability, goals, settings
    func comparabilityLinks() -> [ComparabilityLink]
    func insertComparabilityLink(_ link: ComparabilityLink) throws
    func deleteComparabilityLink(id: UUID) throws
    func goals() -> [Goal]
    func upsertGoal(_ goal: Goal) throws
    func deleteGoal(id: UUID) throws
    func settings() -> UserSettings
    func saveSettings(_ settings: UserSettings) throws

    /// Full snapshot (export / backup).
    func snapshot() -> GymDatabase
    /// Replace or merge from a snapshot (import / restore). Implementations must be all-or-nothing.
    func merge(_ database: GymDatabase) throws
}

extension GymRepository {
    /// All sets of a session, grouped by log.
    public func setLogs(sessionId: UUID) -> [UUID: [SetLog]] {
        Dictionary(uniqueKeysWithValues: exerciseLogs(sessionId: sessionId).map { ($0.id, setLogs(exerciseLogId: $0.id)) })
    }

    public func hasHistory(exerciseId: UUID) -> Bool {
        !exerciseLogs(exerciseId: exerciseId).isEmpty
    }

    public func hasHistory(routineId: UUID) -> Bool {
        sessions().contains { $0.routineId == routineId }
    }
}
