import Foundation
import GymCore

/// `GymRepository` backed by an in-memory store, optionally persisted to a JSON file after every
/// mutation (atomic write). Used by tests (reload from disk = "reopen the app") and as a reference
/// implementation of the repository contract. The iOS app uses `SwiftDataGymRepository`.
@MainActor
public final class JSONGymRepository: GymRepository {
    private var exercisesById: [UUID: Exercise] = [:]
    private var routinesById: [UUID: RoutineTemplate] = [:]
    private var routineExercisesById: [UUID: RoutineExercise] = [:]
    private var scheduleById: [UUID: ScheduleEntry] = [:]
    private var sessionsById: [UUID: WorkoutSession] = [:]
    private var logsById: [UUID: ExerciseLog] = [:]
    private var setsById: [UUID: SetLog] = [:]
    private var decisionsByLog: [UUID: RecommendationDecision] = [:]
    private var linksById: [UUID: ComparabilityLink] = [:]
    private var goalsById: [UUID: Goal] = [:]
    private var userSettings = UserSettings.default

    private let fileURL: URL?
    private var batchDepth = 0
    private var dirty = false

    /// - Parameter fileURL: `nil` = memory only. Otherwise the file is loaded if it exists.
    public init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let db = try GymJSON.decoder.decode(GymDatabase.self, from: data)
            guard db.schemaVersion <= GymSchema.currentVersion else {
                throw GymStoreError.unsupportedSchemaVersion(db.schemaVersion)
            }
            load(db)
        }
    }

    /// Groups many writes into one disk write (seeding, imports, generators).
    public func batch(_ body: () throws -> Void) throws {
        batchDepth += 1
        defer { batchDepth -= 1 }
        try body()
        if batchDepth == 1, dirty { try persist() }
    }

    // MARK: Catalog

    public func exercises() -> [Exercise] { exercisesById.values.sorted(by: Self.byName) }
    public func exercise(id: UUID) -> Exercise? { exercisesById[id] }
    public func upsertExercise(_ exercise: Exercise) throws { try mutate { exercisesById[exercise.id] = exercise } }
    public func deleteExercise(id: UUID) throws {
        guard !hasHistory(exerciseId: id) else { throw GymStoreError.hasHistory }
        try mutate {
            exercisesById[id] = nil
            for item in routineExercisesById.values where item.exerciseId == id { routineExercisesById[item.id] = nil }
        }
    }

    // MARK: Routines

    public func routines() -> [RoutineTemplate] {
        routinesById.values.sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) }
    }
    public func routine(id: UUID) -> RoutineTemplate? { routinesById[id] }
    public func upsertRoutine(_ routine: RoutineTemplate) throws { try mutate { routinesById[routine.id] = routine } }
    public func deleteRoutine(id: UUID) throws {
        guard !hasHistory(routineId: id) else { throw GymStoreError.hasHistory }
        try mutate {
            routinesById[id] = nil
            for item in routineExercisesById.values where item.routineId == id { routineExercisesById[item.id] = nil }
        }
    }
    public func routineExercises(routineId: UUID) -> [RoutineExercise] {
        routineExercisesById.values.filter { $0.routineId == routineId }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
    }
    public func routineExercise(id: UUID) -> RoutineExercise? { routineExercisesById[id] }
    public func upsertRoutineExercise(_ item: RoutineExercise) throws { try mutate { routineExercisesById[item.id] = item } }
    public func deleteRoutineExercise(id: UUID) throws { try mutate { routineExercisesById[id] = nil } }

    // MARK: Schedule

    public func scheduleEntries() -> [ScheduleEntry] {
        scheduleById.values.sorted { ($0.validFrom, $0.createdAt, $0.id.uuidString) < ($1.validFrom, $1.createdAt, $1.id.uuidString) }
    }
    public func insertScheduleEntry(_ entry: ScheduleEntry) throws {
        guard scheduleById[entry.id] == nil else { throw GymStoreError.invalidValue("El calendario no se reescribe: se agregan entradas nuevas.") }
        try mutate { scheduleById[entry.id] = entry }
    }

    // MARK: History

    public func sessions() -> [WorkoutSession] {
        sessionsById.values.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
    }
    public func session(id: UUID) -> WorkoutSession? { sessionsById[id] }
    public func upsertSession(_ session: WorkoutSession) throws { try mutate { sessionsById[session.id] = session } }

    public func exerciseLogs(sessionId: UUID) -> [ExerciseLog] {
        (logIdsBySession[sessionId] ?? []).compactMap { logsById[$0] }
            .sorted { ($0.plannedOrder, $0.id.uuidString) < ($1.plannedOrder, $1.id.uuidString) }
    }
    public func exerciseLogs(exerciseId: UUID) -> [ExerciseLog] {
        (logIdsByExercise[exerciseId] ?? []).compactMap { logsById[$0] }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    public func exerciseLog(id: UUID) -> ExerciseLog? { logsById[id] }
    public func upsertExerciseLog(_ log: ExerciseLog) throws { try mutate { putLog(log) } }
    public func deleteExerciseLog(id: UUID) throws {
        try mutate {
            for setId in setIdsByLog[id] ?? [] { removeSet(setId) }
            removeLog(id)
            decisionsByLog[id] = nil
        }
    }

    public func setLogs(exerciseLogId: UUID) -> [SetLog] {
        (setIdsByLog[exerciseLogId] ?? []).compactMap { setsById[$0] }
            .sorted { ($0.index, $0.id.uuidString) < ($1.index, $1.id.uuidString) }
    }
    public func setLog(id: UUID) -> SetLog? { setsById[id] }
    public func upsertSetLog(_ set: SetLog) throws { try mutate { putSet(set) } }
    public func deleteSetLog(id: UUID) throws { try mutate { removeSet(id) } }

    // Secondary indexes (parent id → child ids) keep history queries O(children).
    private var logIdsBySession: [UUID: Set<UUID>] = [:]
    private var logIdsByExercise: [UUID: Set<UUID>] = [:]
    private var setIdsByLog: [UUID: Set<UUID>] = [:]

    private func putLog(_ log: ExerciseLog) {
        removeLog(log.id)
        logsById[log.id] = log
        logIdsBySession[log.sessionId, default: []].insert(log.id)
        logIdsByExercise[log.exerciseId, default: []].insert(log.id)
    }

    private func removeLog(_ id: UUID) {
        guard let old = logsById.removeValue(forKey: id) else { return }
        logIdsBySession[old.sessionId]?.remove(id)
        logIdsByExercise[old.exerciseId]?.remove(id)
    }

    private func putSet(_ set: SetLog) {
        removeSet(set.id)
        setsById[set.id] = set
        setIdsByLog[set.exerciseLogId, default: []].insert(set.id)
    }

    private func removeSet(_ id: UUID) {
        guard let old = setsById.removeValue(forKey: id) else { return }
        setIdsByLog[old.exerciseLogId]?.remove(id)
    }

    public func decision(exerciseLogId: UUID) -> RecommendationDecision? { decisionsByLog[exerciseLogId] }
    public func upsertDecision(_ decision: RecommendationDecision) throws { try mutate { decisionsByLog[decision.exerciseLogId] = decision } }

    // MARK: Links, goals, settings

    public func comparabilityLinks() -> [ComparabilityLink] {
        linksById.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
    public func insertComparabilityLink(_ link: ComparabilityLink) throws { try mutate { linksById[link.id] = link } }
    public func deleteComparabilityLink(id: UUID) throws { try mutate { linksById[id] = nil } }

    public func goals() -> [Goal] { goalsById.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } }
    public func upsertGoal(_ goal: Goal) throws { try mutate { goalsById[goal.id] = goal } }
    public func deleteGoal(id: UUID) throws { try mutate { goalsById[id] = nil } }

    public func settings() -> UserSettings { userSettings }
    public func saveSettings(_ settings: UserSettings) throws { try mutate { userSettings = settings } }

    // MARK: Snapshot

    public func snapshot() -> GymDatabase {
        GymDatabase(
            schemaVersion: GymSchema.currentVersion,
            exercises: exercises(),
            routines: routines(),
            routineExercises: routineExercisesById.values.sorted { $0.id.uuidString < $1.id.uuidString },
            schedule: scheduleEntries(),
            sessions: sessions(),
            exerciseLogs: logsById.values.sorted { $0.id.uuidString < $1.id.uuidString },
            setLogs: setsById.values.sorted { $0.id.uuidString < $1.id.uuidString },
            decisions: decisionsByLog.values.sorted { $0.id.uuidString < $1.id.uuidString },
            comparabilityLinks: comparabilityLinks(),
            goals: goals(),
            settings: userSettings
        )
    }

    /// Inserts only records whose id does not exist yet; existing records are never overwritten
    /// (an older backup can never undo newer local history). All-or-nothing.
    public func merge(_ database: GymDatabase, includeSettings: Bool) throws {
        let backup = snapshot()
        var missing = database
        missing.exercises = database.exercises.filter { exercisesById[$0.id] == nil }
        missing.routines = database.routines.filter { routinesById[$0.id] == nil }
        missing.routineExercises = database.routineExercises.filter { routineExercisesById[$0.id] == nil }
        missing.schedule = database.schedule.filter { scheduleById[$0.id] == nil }
        missing.sessions = database.sessions.filter { sessionsById[$0.id] == nil }
        missing.exerciseLogs = database.exerciseLogs.filter { logsById[$0.id] == nil }
        missing.setLogs = database.setLogs.filter { setsById[$0.id] == nil }
        missing.decisions = database.decisions.filter { decisionsByLog[$0.exerciseLogId] == nil }
        missing.comparabilityLinks = database.comparabilityLinks.filter { linksById[$0.id] == nil }
        missing.goals = database.goals.filter { goalsById[$0.id] == nil }
        do {
            try batch {
                try mutate { apply(missing, settings: includeSettings) }
            }
        } catch {
            clear()
            load(backup)
            throw error
        }
    }

    // MARK: Internals

    private func clear() {
        exercisesById = [:]; routinesById = [:]; routineExercisesById = [:]; scheduleById = [:]
        sessionsById = [:]; logsById = [:]; setsById = [:]; decisionsByLog = [:]; linksById = [:]; goalsById = [:]
        logIdsBySession = [:]; logIdsByExercise = [:]; setIdsByLog = [:]
        userSettings = .default
    }

    private func load(_ db: GymDatabase) {
        apply(db, settings: true)
    }

    private func apply(_ db: GymDatabase, settings: Bool) {
        for e in db.exercises { exercisesById[e.id] = e }
        for r in db.routines { routinesById[r.id] = r }
        for r in db.routineExercises { routineExercisesById[r.id] = r }
        for s in db.schedule { scheduleById[s.id] = s }
        for s in db.sessions { sessionsById[s.id] = s }
        for l in db.exerciseLogs { putLog(l) }
        for s in db.setLogs { putSet(s) }
        for d in db.decisions { decisionsByLog[d.exerciseLogId] = d }
        for l in db.comparabilityLinks { linksById[l.id] = l }
        for g in db.goals { goalsById[g.id] = g }
        if settings { userSettings = db.settings }
    }

    /// Applies a change and persists it. If the disk write fails, memory is restored to the last
    /// state on disk so memory never claims something that was not saved.
    private func mutate(_ change: () -> Void) throws {
        change()
        dirty = true
        guard batchDepth == 0 else { return }
        do {
            try persist()
        } catch {
            restoreFromDisk()
            throw error
        }
    }

    private func restoreFromDisk() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let db = try? GymJSON.decoder.decode(GymDatabase.self, from: data) else { return }
        clear()
        load(db)
    }

    private func persist() throws {
        defer { dirty = false }
        guard let fileURL else { return }
        do {
            let data = try GymJSON.encoder.encode(snapshot())
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw GymStoreError.storage(String(describing: error))
        }
    }

    private static func byName(_ a: Exercise, _ b: Exercise) -> Bool {
        let c = a.name.localizedCompare(b.name)
        return c == .orderedSame ? a.id.uuidString < b.id.uuidString : c == .orderedAscending
    }
}

/// Shared JSON configuration (export/import and the JSON store): dates as seconds since 1970 (UTC,
/// lossless for sub-second instants), sorted keys for stable diffs.
public enum GymJSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(date.timeIntervalSince1970)
        }
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try c.decode(Double.self))
        }
        return d
    }
}
