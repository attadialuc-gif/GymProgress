import Foundation
import GymCore

/// The user's answer to a recommendation.
public enum DecisionChoice: Sendable, Hashable {
    /// Pre-fill the recommended load; recommended reps stay visible as targets.
    case accept
    /// Use the user's own load / reps (or seconds) as today's target.
    case modify(weight: Double?, reps: [Int], seconds: [Int]? = nil)
    /// Pre-fill nothing.
    case ignore
}

/// Everything the exercise screen needs, with the recommendation card on top.
public struct ExerciseLogState: Sendable, Hashable {
    public var log: ExerciseLog
    public var sets: [SetLog]
    /// Frozen when the exercise was first opened; never recomputed afterwards (except on a context
    /// change before any decision).
    public var recommendation: Recommendation
    public var decision: RecommendationDecision?
}

/// Session flow. Every call persists immediately through the repository (incremental save).
/// "Now" is always injected.
@MainActor
public final class WorkoutService {
    public let repository: any GymRepository
    public var timeZone: TimeZone
    public var locale: Locale

    public init(repository: any GymRepository, timeZone: TimeZone = .current, locale: Locale = GymFormat.defaultLocale) {
        self.repository = repository
        self.timeZone = timeZone
        self.locale = locale
    }

    private var history: HistoryService { HistoryService(repository: repository) }

    public var calendar: TrainingCalendar {
        TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday, locale: locale)
    }

    // MARK: - Session lifecycle

    /// The session to resume after a crash, call or lock (active or paused). At most one exists.
    public func openSession() -> WorkoutSession? {
        repository.sessions().filter(\.isOpen).max { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
    }

    @discardableResult
    public func startSession(routineId: UUID?, now: Date) throws -> WorkoutSession {
        guard openSession() == nil else { throw GymStoreError.sessionAlreadyOpen }
        var routineName: String?
        var items: [RoutineExercise] = []
        if let routineId {
            guard let routine = repository.routine(id: routineId) else { throw GymStoreError.notFound("routine") }
            routineName = routine.name
            items = repository.routineExercises(routineId: routineId)
        }
        let session = WorkoutSession(routineId: routineId, routineNameSnapshot: routineName, startedAt: now, status: .active, updatedAt: now)
        try repository.upsertSession(session)

        var order = 0
        for item in items {
            guard let exercise = repository.exercise(id: item.exerciseId), !exercise.isArchived else { continue }
            let config = item.progressionOverride ?? exercise.progression
            try createLog(session: session, exercise: exercise, config: config, routineExerciseId: item.id, restSeconds: item.restSeconds ?? exercise.defaultRestSeconds, notes: item.notes, order: order)
            order += 1
        }
        return session
    }

    public func pause(sessionId: UUID, now: Date) throws {
        var session = try openSession(id: sessionId)
        guard session.status == .active else { return }
        session.status = .paused
        session.pauses.append(PauseInterval(start: now))
        session.updatedAt = now
        try repository.upsertSession(session)
    }

    public func resume(sessionId: UUID, now: Date) throws {
        var session = try openSession(id: sessionId)
        guard session.status == .paused else { return }
        closePause(&session, at: now)
        session.status = .active
        session.updatedAt = now
        try repository.upsertSession(session)
    }

    @discardableResult
    public func finish(sessionId: UUID, now: Date) throws -> WorkoutSession {
        var session = try openSession(id: sessionId)
        closePause(&session, at: now)
        session.status = .completed
        session.endedAt = now
        session.updatedAt = now
        try repository.upsertSession(session)
        return session
    }

    /// Marks the session as discarded (kept for audit, excluded everywhere). The UI must confirm first.
    public func discard(sessionId: UUID, now: Date) throws {
        var session = try openSession(id: sessionId)
        closePause(&session, at: now)
        session.status = .discarded
        session.endedAt = now
        session.updatedAt = now
        try repository.upsertSession(session)
    }

    public func setSessionNotes(sessionId: UUID, notes: String, now: Date) throws {
        guard var session = repository.session(id: sessionId) else { throw GymStoreError.notFound("session") }
        session.notes = notes
        session.updatedAt = now
        try repository.upsertSession(session)
    }

    public func setSessionAtypical(sessionId: UUID, _ atypical: Bool, now: Date) throws {
        guard var session = repository.session(id: sessionId) else { throw GymStoreError.notFound("session") }
        session.isAtypical = atypical
        session.updatedAt = now
        try repository.upsertSession(session)
    }

    // MARK: - Exercises inside a session (session-only changes; the template is never touched)

    @discardableResult
    public func addExercise(sessionId: UUID, exerciseId: UUID, now: Date) throws -> ExerciseLog {
        let session = try openSession(id: sessionId)
        guard let exercise = repository.exercise(id: exerciseId) else { throw GymStoreError.notFound("exercise") }
        let order = (repository.exerciseLogs(sessionId: sessionId).map(\.plannedOrder).max() ?? -1) + 1
        return try createLog(session: session, exercise: exercise, config: exercise.progression, routineExerciseId: nil, restSeconds: exercise.defaultRestSeconds, notes: "", order: order)
    }

    /// Removes an exercise from this session only. Refused once a set was completed (data integrity).
    public func removeExercise(logId: UUID) throws {
        guard repository.exerciseLog(id: logId) != nil else { throw GymStoreError.notFound("exerciseLog") }
        guard !repository.setLogs(exerciseLogId: logId).contains(where: { $0.status == .completed }) else {
            throw GymStoreError.hasCompletedSets
        }
        try repository.deleteExerciseLog(id: logId)
    }

    public func moveExercises(sessionId: UUID, orderedLogIds: [UUID]) throws {
        for (i, id) in orderedLogIds.enumerated() {
            guard var log = repository.exerciseLog(id: id), log.sessionId == sessionId else { continue }
            if log.plannedOrder != i {
                log.plannedOrder = i
                try repository.upsertExerciseLog(log)
            }
        }
    }

    public func setExerciseNotes(logId: UUID, notes: String) throws {
        var log = try requireLog(logId)
        log.notes = notes
        try repository.upsertExerciseLog(log)
    }

    public func setExerciseAtypical(logId: UUID, _ atypical: Bool) throws {
        var log = try requireLog(logId)
        log.isAtypical = atypical
        try repository.upsertExerciseLog(log)
    }

    /// Changes the comparability context (machine / variant). Before any decision the recommendation
    /// is recomputed for the new context; after a decision, the decision and the frozen
    /// recommendation are kept untouched (the user's choice is the source of truth).
    @discardableResult
    public func setContext(logId: UUID, variantLabel: String?, equipmentLabel: String?, now: Date) throws -> ExerciseLog {
        var log = try requireLog(logId)
        log.variantLabel = Self.cleanLabel(variantLabel)
        log.equipmentLabel = Self.cleanLabel(equipmentLabel)
        if log.frozenRecommendation != nil, repository.decision(exerciseLogId: logId) == nil {
            log.frozenRecommendation = computeRecommendation(for: log, now: now)
            log.recommendationFrozenAt = now
        }
        try repository.upsertExerciseLog(log)
        return log
    }

    /// Manual "treat as equivalent" between two contexts. Only created by explicit user action.
    @discardableResult
    public func linkContexts(_ a: ComparabilityContext, _ b: ComparabilityContext, now: Date) throws -> ComparabilityLink {
        let link = ComparabilityLink(a: a, b: b, createdAt: now)
        try repository.insertComparabilityLink(link)
        return link
    }

    // MARK: - Recommendation

    /// Opens an exercise: computes the recommendation with history *prior* to this session and
    /// freezes it in the log the first time. Re-opening returns the frozen one and the decision.
    public func openExercise(logId: UUID, now: Date) throws -> ExerciseLogState {
        var log = try requireLog(logId)
        if log.frozenRecommendation == nil {
            log.frozenRecommendation = computeRecommendation(for: log, now: now)
            log.recommendationFrozenAt = now
            try repository.upsertExerciseLog(log)
        }
        return state(of: log)
    }

    /// Persists the user's decision and applies it to the pending sets. Changing one's mind updates
    /// the same decision (the originally shown recommendation stays as the audit snapshot).
    @discardableResult
    public func decide(logId: UUID, choice: DecisionChoice, now: Date) throws -> RecommendationDecision {
        var log = try requireLog(logId)
        if log.frozenRecommendation == nil {
            log.frozenRecommendation = computeRecommendation(for: log, now: now)
            log.recommendationFrozenAt = now
            try repository.upsertExerciseLog(log)
        }
        guard let recommendation = log.frozenRecommendation else { throw GymStoreError.notFound("recommendation") }

        let kind: DecisionKind
        var weight: Double?
        var reps: [Int]
        var seconds: [Int]?
        switch choice {
        case .accept:
            kind = .accepted
            weight = recommendation.targetWeight
            reps = recommendation.targetReps
            seconds = recommendation.targetSeconds
        case let .modify(w, r, s):
            kind = .modified
            if let w {
                guard w.isFinite, w >= 0 || log.snapshot.measurement == .bodyweightReps else { throw GymStoreError.invalidValue("weight") }
            }
            guard r.allSatisfy({ $0 >= 0 }), (s ?? []).allSatisfy({ $0 >= 0 }) else { throw GymStoreError.invalidValue("reps") }
            weight = w.map(LoadMath.normalized)
            reps = r
            seconds = s
        case .ignore:
            kind = .ignored
            weight = nil
            reps = []
            seconds = nil
        }

        let previous = repository.decision(exerciseLogId: logId)
        let decision = RecommendationDecision(
            id: previous?.id ?? UUID(),
            exerciseLogId: logId,
            recommended: previous?.recommended ?? RecommendationSnapshot(recommendation),
            kind: kind,
            finalWeight: weight,
            finalReps: reps,
            finalSeconds: seconds,
            decidedAt: now
        )
        try repository.upsertDecision(decision)
        try applyDecision(decision, previous: previous, to: log)
        return decision
    }

    /// Copies the loads (and reps as targets) of the last comparable session into the pending sets.
    /// Falls back to the last session in another context only because the user asked explicitly.
    public func copyPreviousLoads(logId: UUID, now: Date) throws {
        let state = try openExercise(logId: logId, now: now)
        guard let previous = state.recommendation.lastPerformance ?? state.recommendation.nonEquivalentReference,
              !previous.sets.isEmpty else { throw GymStoreError.notFound("previous performance") }
        let measurement = state.log.snapshot.measurement
        try ensureWorkingSets(count: previous.sets.count, log: state.log)
        for (i, set) in workingSets(of: state.log).enumerated() where set.status == .pending {
            var s = set
            let source = previous.sets[min(i, previous.sets.count - 1)]
            setLoad(&s, source.load, measurement: measurement)
            if i < previous.sets.count {
                if measurement == .duration { s.targetSeconds = source.amount } else { s.targetReps = source.amount }
            }
            try repository.upsertSetLog(s)
        }
    }

    /// Recommendation for the *next* session (Home / routine preview / after finishing). Not frozen.
    public func previewRecommendation(exerciseId: UUID, config: ProgressionConfig? = nil, now: Date) -> Recommendation? {
        guard let exercise = repository.exercise(id: exerciseId) else { return nil }
        let labels = history.lastUsedLabels(exerciseId: exerciseId)
        let context = ComparabilityContext(exerciseId: exerciseId, variantLabel: labels.variant, equipmentLabel: labels.equipment, loadMode: exercise.loadMode)
        return recommendation(context: context, measurement: exercise.measurement, config: config ?? exercise.progression, excludingSessionId: nil, now: now)
    }

    /// Preview for every exercise of a routine (routine preview / Home).
    public func previewRecommendations(routineId: UUID, now: Date) -> [(RoutineExercise, Exercise, Recommendation)] {
        repository.routineExercises(routineId: routineId).compactMap { item in
            guard let exercise = repository.exercise(id: item.exerciseId), !exercise.isArchived,
                  let rec = previewRecommendation(exerciseId: exercise.id, config: item.progressionOverride ?? exercise.progression, now: now)
            else { return nil }
            return (item, exercise, rec)
        }
    }

    // MARK: - Sets

    @discardableResult
    public func addSet(logId: UUID, kind: SetKind = .working) throws -> SetLog {
        _ = try requireLog(logId)
        let sets = repository.setLogs(exerciseLogId: logId)
        let last = sets.last { $0.kind == kind } ?? sets.last
        let set = SetLog(
            exerciseLogId: logId,
            index: (sets.map(\.index).max() ?? -1) + 1,
            kind: kind,
            weight: kind == .warmup ? nil : last?.weight,
            addedWeight: last?.addedWeight,
            assistance: last?.assistance
        )
        try repository.upsertSetLog(set)
        return set
    }

    /// Saves edited values. Negative values are rejected; unusual values are allowed (the UI warns).
    public func updateSet(_ set: SetLog) throws {
        guard let existing = repository.setLog(id: set.id) else { throw GymStoreError.notFound("set") }
        try Self.validate(set)
        var updated = set
        updated.exerciseLogId = existing.exerciseLogId
        updated.weight = set.weight.map(LoadMath.normalized)
        updated.addedWeight = set.addedWeight.map(LoadMath.normalized)
        updated.assistance = set.assistance.map(LoadMath.normalized)
        try repository.upsertSetLog(updated)
    }

    public func removeSet(setId: UUID) throws {
        guard let set = repository.setLog(id: setId) else { throw GymStoreError.notFound("set") }
        try repository.deleteSetLog(id: setId)
        for (i, remaining) in repository.setLogs(exerciseLogId: set.exerciseLogId).enumerated() where remaining.index != i {
            var s = remaining
            s.index = i
            try repository.upsertSetLog(s)
        }
    }

    /// One-tap completion: missing reps/seconds are taken from the visible target. Records the real
    /// execution order of the exercise on its first completed set.
    @discardableResult
    public func completeSet(setId: UUID, now: Date) throws -> SetLog {
        guard var set = repository.setLog(id: setId) else { throw GymStoreError.notFound("set") }
        var log = try requireLog(set.exerciseLogId)
        let measurement = log.snapshot.measurement
        switch measurement {
        case .weightReps:
            if set.reps == nil { set.reps = set.targetReps }
            guard set.weight != nil, set.reps != nil else { throw GymStoreError.missingValues }
        case .bodyweightReps:
            if set.reps == nil { set.reps = set.targetReps }
            guard set.reps != nil else { throw GymStoreError.missingValues }
        case .duration:
            if set.seconds == nil { set.seconds = set.targetSeconds }
            guard set.seconds != nil else { throw GymStoreError.missingValues }
        }
        try Self.validate(set)
        set.status = .completed
        set.completedAt = now
        try repository.upsertSetLog(set)

        if log.executionOrder == nil {
            let used = repository.exerciseLogs(sessionId: log.sessionId).compactMap(\.executionOrder)
            log.executionOrder = (used.max() ?? -1) + 1
            try repository.upsertExerciseLog(log)
        }
        if var session = repository.session(id: log.sessionId) {
            session.updatedAt = now
            try repository.upsertSession(session)
        }
        return set
    }

    public func reopenSet(setId: UUID) throws {
        guard var set = repository.setLog(id: setId) else { throw GymStoreError.notFound("set") }
        set.status = .pending
        set.completedAt = nil
        try repository.upsertSetLog(set)
    }

    // MARK: - Internals

    func computeRecommendation(for log: ExerciseLog, now: Date) -> Recommendation {
        recommendation(context: log.context, measurement: log.snapshot.measurement, config: log.configSnapshot, excludingSessionId: log.sessionId, now: now)
    }

    private func recommendation(context: ComparabilityContext, measurement: MeasurementType, config: ProgressionConfig, excludingSessionId: UUID?, now: Date) -> Recommendation {
        let settings = repository.settings()
        let input = ProgressionInput(
            context: context,
            measurement: measurement,
            config: config,
            history: history.performances(exerciseId: context.exerciseId),
            links: repository.comparabilityLinks(),
            now: now,
            excludingSessionId: excludingSessionId,
            calendar: calendar.calendar,
            locale: locale,
            oneRepMax: settings.oneRepMax
        )
        return ProgressionEngine.recommend(input)
    }

    @discardableResult
    private func createLog(session: WorkoutSession, exercise: Exercise, config: ProgressionConfig, routineExerciseId: UUID?, restSeconds: Int?, notes: String, order: Int) throws -> ExerciseLog {
        let labels = history.lastUsedLabels(exerciseId: exercise.id)
        let sanitized = config.sanitized()
        let log = ExerciseLog(
            sessionId: session.id,
            exerciseId: exercise.id,
            routineExerciseId: routineExerciseId,
            snapshot: ExerciseSnapshot(exercise),
            configSnapshot: sanitized,
            variantLabel: labels.variant,
            equipmentLabel: labels.equipment,
            plannedOrder: order,
            restSeconds: restSeconds,
            notes: notes
        )
        try repository.upsertExerciseLog(log)
        for i in 0..<sanitized.targetSets {
            try repository.upsertSetLog(SetLog(exerciseLogId: log.id, index: i, kind: .working))
        }
        return log
    }

    /// Only called after the recommendation was frozen (see `openExercise`).
    private func state(of log: ExerciseLog) -> ExerciseLogState {
        guard let recommendation = log.frozenRecommendation else {
            preconditionFailure("state(of:) requires a frozen recommendation")
        }
        return ExerciseLogState(
            log: log,
            sets: repository.setLogs(exerciseLogId: log.id),
            recommendation: recommendation,
            decision: repository.decision(exerciseLogId: log.id)
        )
    }

    private func workingSets(of log: ExerciseLog) -> [SetLog] {
        repository.setLogs(exerciseLogId: log.id).filter { $0.kind == .working }
    }

    private func ensureWorkingSets(count: Int, log: ExerciseLog) throws {
        let existing = workingSets(of: log).count
        guard existing < count else { return }
        for _ in existing..<count { try addSet(logId: log.id, kind: .working) }
    }

    private func applyDecision(_ decision: RecommendationDecision, previous: RecommendationDecision?, to log: ExerciseLog) throws {
        let measurement = log.snapshot.measurement
        switch decision.kind {
        case .accepted, .modified:
            let targetCount = max(decision.finalReps.count, decision.finalSeconds?.count ?? 0)
            try ensureWorkingSets(count: targetCount, log: log)
            for (i, set) in workingSets(of: log).enumerated() where set.status == .pending {
                var s = set
                if let w = decision.finalWeight { setLoad(&s, w, measurement: measurement) }
                s.targetReps = i < decision.finalReps.count ? decision.finalReps[i] : nil
                s.targetSeconds = decision.finalSeconds.flatMap { i < $0.count ? $0[i] : nil }
                try repository.upsertSetLog(s)
            }
        case .ignored:
            for set in workingSets(of: log) where set.status == .pending {
                var s = set
                s.targetReps = nil
                s.targetSeconds = nil
                if let w = previous?.finalWeight, previous?.kind != .ignored, loadMatches(s, w, measurement: measurement) {
                    clearLoad(&s, measurement: measurement)
                }
                try repository.upsertSetLog(s)
            }
        }
    }

    private func setLoad(_ set: inout SetLog, _ load: Double, measurement: MeasurementType) {
        switch measurement {
        case .weightReps, .duration:
            set.weight = LoadMath.normalized(load)
        case .bodyweightReps:
            let k = LoadMath.key(load)
            set.addedWeight = k > 0 ? LoadMath.normalized(load) : nil
            set.assistance = k < 0 ? LoadMath.normalized(-load) : nil
        }
    }

    private func loadMatches(_ set: SetLog, _ load: Double, measurement: MeasurementType) -> Bool {
        switch measurement {
        case .weightReps, .duration: set.weight.map { LoadMath.isEqual($0, load) } ?? false
        case .bodyweightReps: LoadMath.isEqual(set.performed.netAddedLoad, load)
        }
    }

    private func clearLoad(_ set: inout SetLog, measurement: MeasurementType) {
        switch measurement {
        case .weightReps, .duration: set.weight = nil
        case .bodyweightReps: set.addedWeight = nil; set.assistance = nil
        }
    }

    private func closePause(_ session: inout WorkoutSession, at now: Date) {
        if let i = session.pauses.lastIndex(where: { $0.end == nil }) {
            session.pauses[i].end = now
        }
    }

    private func openSession(id: UUID) throws -> WorkoutSession {
        guard let session = repository.session(id: id) else { throw GymStoreError.notFound("session") }
        guard session.isOpen else { throw GymStoreError.sessionNotOpen }
        return session
    }

    private func requireLog(_ id: UUID) throws -> ExerciseLog {
        guard let log = repository.exerciseLog(id: id) else { throw GymStoreError.notFound("exerciseLog") }
        return log
    }

    static func cleanLabel(_ label: String?) -> String? {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func validate(_ set: SetLog) throws {
        let issues = SetValidator.validate(weight: set.weight, reps: set.reps, seconds: set.seconds, rir: set.rir, rpe: set.rpe)
        if let error = issues.first(where: \.isError), case let .error(message) = error {
            throw GymStoreError.invalidValue(message)
        }
        if let a = set.addedWeight, !(a.isFinite && a >= 0) { throw GymStoreError.invalidValue("addedWeight") }
        if let a = set.assistance, !(a.isFinite && a >= 0) { throw GymStoreError.invalidValue("assistance") }
    }
}
