import Foundation
import GymCore

/// One exercise as performed in a past session, for history screens.
public struct ExerciseHistoryEntry: Sendable, Hashable, Identifiable {
    public var id: UUID { log.id }
    public var session: WorkoutSession
    public var log: ExerciseLog
    public var sets: [SetLog]
    public var decision: RecommendationDecision?
    public var performance: ExercisePerformance
}

/// Read-side mapping from records to GymCore inputs. No business rules here: it only translates.
@MainActor
public struct HistoryService {
    public let repository: any GymRepository

    public init(repository: any GymRepository) {
        self.repository = repository
    }

    /// Every log of the exercise, in any context and any session status. The engine and the metrics
    /// decide what is comparable / valid.
    public func performances(exerciseId: UUID) -> [ExercisePerformance] {
        repository.exerciseLogs(exerciseId: exerciseId).compactMap { log in
            repository.session(id: log.sessionId).map { performance(of: log, in: $0) }
        }
    }

    public func performance(of log: ExerciseLog, in session: WorkoutSession) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: session.id,
            exerciseLogId: log.id,
            sessionStart: session.startedAt,
            sessionStatus: session.status,
            isAtypical: session.isAtypical || log.isAtypical,
            context: log.context,
            measurement: log.snapshot.measurement,
            sets: repository.setLogs(exerciseLogId: log.id).map(\.performed)
        )
    }

    /// Completed sessions of the exercise, newest first, with their sets and decisions.
    public func exerciseHistory(exerciseId: UUID) -> [ExerciseHistoryEntry] {
        repository.exerciseLogs(exerciseId: exerciseId)
            .compactMap { log -> ExerciseHistoryEntry? in
                guard let session = repository.session(id: log.sessionId), session.status == .completed else { return nil }
                return ExerciseHistoryEntry(
                    session: session,
                    log: log,
                    sets: repository.setLogs(exerciseLogId: log.id),
                    decision: repository.decision(exerciseLogId: log.id),
                    performance: performance(of: log, in: session)
                )
            }
            .sorted { a, b in
                a.session.startedAt != b.session.startedAt ? a.session.startedAt > b.session.startedAt : a.log.id.uuidString < b.log.id.uuidString
            }
    }

    /// Digest of every session (consistency metrics).
    public func sessionDigests() -> [SessionDigest] {
        repository.sessions().map { session in
            let effective = repository.exerciseLogs(sessionId: session.id).reduce(0) { acc, log in
                acc + repository.setLogs(exerciseLogId: log.id).filter { $0.performed.isEffective(for: log.snapshot.measurement) }.count
            }
            return SessionDigest(id: session.id, start: session.startedAt, status: session.status, effectiveSets: effective, routineId: session.routineId)
        }
    }

    /// Muscle work of completed sessions starting in `interval` (muscles from the log snapshot).
    public func muscleWork(in interval: DateInterval) -> [MuscleWork] {
        repository.sessions()
            .filter { $0.status == .completed && interval.contains($0.startedAt) }
            .flatMap { session in
                repository.exerciseLogs(sessionId: session.id).map { log in
                    MuscleWork(performance: performance(of: log, in: session), primary: log.snapshot.primaryMuscles, secondary: log.snapshot.secondaryMuscles)
                }
            }
    }

    /// Labels of the most recent log of this exercise (default context for a new log, so a user who
    /// always trains on "Máquina A" keeps comparing against it without re-selecting it).
    public func lastUsedLabels(exerciseId: UUID) -> (variant: String?, equipment: String?) {
        let latest = repository.exerciseLogs(exerciseId: exerciseId)
            .compactMap { log -> (ExerciseLog, Date)? in
                guard let s = repository.session(id: log.sessionId), s.status == .completed else { return nil }
                return (log, s.startedAt)
            }
            .max { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.id.uuidString < b.0.id.uuidString }
        return (latest?.0.variantLabel, latest?.0.equipmentLabel)
    }
}
