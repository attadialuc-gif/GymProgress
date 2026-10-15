import Foundation
import GymCore
import GymStore
import OSLog
import SwiftData

/// `GymRepository` on SwiftData. Every mutation saves the context immediately (incremental save):
/// a completed set or a recommendation decision is on disk before the call returns.
///
/// UNVERIFIED: written without Xcode. Behaviour contract = `JSONGymRepository` (verified by the
/// GymStore tests); `AppTests/SwiftDataRepositoryTests.swift` runs the same scenarios here on a Mac.
@MainActor
final class SwiftDataGymRepository: GymRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = GymJSON.encoder
    private let decoder = GymJSON.decoder

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        self.context.autosaveEnabled = false
    }

    /// Persistent container for the app (or in-memory for tests and previews).
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: GymMigrationPlan.self, configurations: [configuration])
    }

    // MARK: - Catalog

    func exercises() -> [Exercise] {
        fetch(ExerciseModel.self).compactMap { decode(Exercise.self, $0.payload) }
            .sorted { a, b in
                let c = a.name.localizedCompare(b.name)
                return c == .orderedSame ? a.id.uuidString < b.id.uuidString : c == .orderedAscending
            }
    }

    func exercise(id: UUID) -> Exercise? {
        exerciseModel(id).flatMap { decode(Exercise.self, $0.payload) }
    }

    func upsertExercise(_ exercise: Exercise) throws {
        let payload = try encode(exercise)
        if let m = exerciseModel(exercise.id) {
            m.catalogId = exercise.catalogId
            m.name = exercise.name
            m.isCustom = exercise.isCustom
            m.isArchived = exercise.isArchived
            m.payload = payload
        } else {
            context.insert(ExerciseModel(id: exercise.id, catalogId: exercise.catalogId, name: exercise.name, isCustom: exercise.isCustom, isArchived: exercise.isArchived, payload: payload))
        }
        try save()
    }

    func deleteExercise(id: UUID) throws {
        guard !hasHistory(exerciseId: id) else { throw GymStoreError.hasHistory }
        if let m = exerciseModel(id) { context.delete(m) }
        let target = id
        for item in fetch(RoutineExerciseModel.self, #Predicate { $0.exerciseId == target }) { context.delete(item) }
        try save()
    }

    // MARK: - Routines

    func routines() -> [RoutineTemplate] {
        fetch(RoutineModel.self).map(routine(from:))
            .sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) }
    }

    func routine(id: UUID) -> RoutineTemplate? {
        routineModel(id).map(routine(from:))
    }

    func upsertRoutine(_ routine: RoutineTemplate) throws {
        if let m = routineModel(routine.id) {
            m.name = routine.name
            m.sortOrder = routine.sortOrder
            m.notes = routine.notes
            m.isArchived = routine.isArchived
            m.createdAt = routine.createdAt
        } else {
            context.insert(RoutineModel(id: routine.id, name: routine.name, sortOrder: routine.sortOrder, notes: routine.notes, isArchived: routine.isArchived, createdAt: routine.createdAt))
        }
        try save()
    }

    func deleteRoutine(id: UUID) throws {
        guard !hasHistory(routineId: id) else { throw GymStoreError.hasHistory }
        if let m = routineModel(id) { context.delete(m) }
        let target = id
        for item in fetch(RoutineExerciseModel.self, #Predicate { $0.routineId == target }) { context.delete(item) }
        try save()
    }

    func routineExercises(routineId: UUID) -> [RoutineExercise] {
        let target = routineId
        return fetch(RoutineExerciseModel.self, #Predicate { $0.routineId == target })
            .compactMap { decode(RoutineExercise.self, $0.payload) }
            .sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
    }

    func routineExercise(id: UUID) -> RoutineExercise? {
        routineExerciseModel(id).flatMap { decode(RoutineExercise.self, $0.payload) }
    }

    func upsertRoutineExercise(_ item: RoutineExercise) throws {
        let payload = try encode(item)
        if let m = routineExerciseModel(item.id) {
            m.routineId = item.routineId
            m.exerciseId = item.exerciseId
            m.sortOrder = item.sortOrder
            m.payload = payload
        } else {
            context.insert(RoutineExerciseModel(id: item.id, routineId: item.routineId, exerciseId: item.exerciseId, sortOrder: item.sortOrder, payload: payload))
        }
        try save()
    }

    func deleteRoutineExercise(id: UUID) throws {
        if let m = routineExerciseModel(id) { context.delete(m) }
        try save()
    }

    // MARK: - Schedule

    func scheduleEntries() -> [ScheduleEntry] {
        fetch(ScheduleEntryModel.self).compactMap { decode(ScheduleEntry.self, $0.payload) }
            .sorted { ($0.validFrom, $0.createdAt, $0.id.uuidString) < ($1.validFrom, $1.createdAt, $1.id.uuidString) }
    }

    func insertScheduleEntry(_ entry: ScheduleEntry) throws {
        let target = entry.id
        guard fetch(ScheduleEntryModel.self, #Predicate { $0.id == target }).isEmpty else {
            throw GymStoreError.invalidValue("Schedule entries are append-only")
        }
        context.insert(ScheduleEntryModel(id: entry.id, validFrom: entry.validFrom, payload: try encode(entry)))
        try save()
    }

    // MARK: - History

    func sessions() -> [WorkoutSession] {
        fetch(SessionModel.self).compactMap { decode(WorkoutSession.self, $0.payload) }
            .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
    }

    func session(id: UUID) -> WorkoutSession? {
        sessionModel(id).flatMap { decode(WorkoutSession.self, $0.payload) }
    }

    func upsertSession(_ session: WorkoutSession) throws {
        let payload = try encode(session)
        if let m = sessionModel(session.id) {
            m.routineId = session.routineId
            m.startedAt = session.startedAt
            m.statusRaw = session.status.rawValue
            m.payload = payload
        } else {
            context.insert(SessionModel(id: session.id, routineId: session.routineId, startedAt: session.startedAt, statusRaw: session.status.rawValue, payload: payload))
        }
        try save()
    }

    func exerciseLogs(sessionId: UUID) -> [ExerciseLog] {
        let target = sessionId
        return fetch(ExerciseLogModel.self, #Predicate { $0.sessionId == target })
            .compactMap { decode(ExerciseLog.self, $0.payload) }
            .sorted { ($0.plannedOrder, $0.id.uuidString) < ($1.plannedOrder, $1.id.uuidString) }
    }

    func exerciseLogs(exerciseId: UUID) -> [ExerciseLog] {
        let target = exerciseId
        return fetch(ExerciseLogModel.self, #Predicate { $0.exerciseId == target })
            .compactMap { decode(ExerciseLog.self, $0.payload) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func exerciseLog(id: UUID) -> ExerciseLog? {
        logModel(id).flatMap { decode(ExerciseLog.self, $0.payload) }
    }

    func upsertExerciseLog(_ log: ExerciseLog) throws {
        let payload = try encode(log)
        if let m = logModel(log.id) {
            m.sessionId = log.sessionId
            m.exerciseId = log.exerciseId
            m.plannedOrder = log.plannedOrder
            m.payload = payload
        } else {
            context.insert(ExerciseLogModel(id: log.id, sessionId: log.sessionId, exerciseId: log.exerciseId, plannedOrder: log.plannedOrder, payload: payload))
        }
        try save()
    }

    func deleteExerciseLog(id: UUID) throws {
        let target = id
        for set in fetch(SetLogModel.self, #Predicate { $0.exerciseLogId == target }) { context.delete(set) }
        for d in fetch(DecisionModel.self, #Predicate { $0.exerciseLogId == target }) { context.delete(d) }
        if let m = logModel(id) { context.delete(m) }
        try save()
    }

    func setLogs(exerciseLogId: UUID) -> [SetLog] {
        let target = exerciseLogId
        return fetch(SetLogModel.self, #Predicate { $0.exerciseLogId == target })
            .compactMap { decode(SetLog.self, $0.payload) }
            .sorted { ($0.index, $0.id.uuidString) < ($1.index, $1.id.uuidString) }
    }

    func setLog(id: UUID) -> SetLog? {
        setModel(id).flatMap { decode(SetLog.self, $0.payload) }
    }

    func upsertSetLog(_ set: SetLog) throws {
        let payload = try encode(set)
        if let m = setModel(set.id) {
            m.exerciseLogId = set.exerciseLogId
            m.index = set.index
            m.payload = payload
        } else {
            context.insert(SetLogModel(id: set.id, exerciseLogId: set.exerciseLogId, index: set.index, payload: payload))
        }
        try save()
    }

    func deleteSetLog(id: UUID) throws {
        if let m = setModel(id) { context.delete(m) }
        try save()
    }

    func decision(exerciseLogId: UUID) -> RecommendationDecision? {
        let target = exerciseLogId
        return fetch(DecisionModel.self, #Predicate { $0.exerciseLogId == target }).first
            .flatMap { decode(RecommendationDecision.self, $0.payload) }
    }

    func upsertDecision(_ decision: RecommendationDecision) throws {
        let payload = try encode(decision)
        let target = decision.exerciseLogId
        if let m = fetch(DecisionModel.self, #Predicate { $0.exerciseLogId == target }).first {
            m.id = decision.id
            m.decidedAt = decision.decidedAt
            m.payload = payload
        } else {
            context.insert(DecisionModel(exerciseLogId: decision.exerciseLogId, id: decision.id, decidedAt: decision.decidedAt, payload: payload))
        }
        try save()
    }

    // MARK: - Links, goals, settings

    func comparabilityLinks() -> [ComparabilityLink] {
        fetch(ComparabilityLinkModel.self).compactMap { decode(ComparabilityLink.self, $0.payload) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    func insertComparabilityLink(_ link: ComparabilityLink) throws {
        let target = link.id
        if let m = fetch(ComparabilityLinkModel.self, #Predicate { $0.id == target }).first {
            m.payload = try encode(link)
        } else {
            context.insert(ComparabilityLinkModel(id: link.id, createdAt: link.createdAt, payload: try encode(link)))
        }
        try save()
    }

    func deleteComparabilityLink(id: UUID) throws {
        let target = id
        for m in fetch(ComparabilityLinkModel.self, #Predicate { $0.id == target }) { context.delete(m) }
        try save()
    }

    func goals() -> [Goal] {
        fetch(GoalModel.self).compactMap { decode(Goal.self, $0.payload) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    func upsertGoal(_ goal: Goal) throws {
        let target = goal.id
        if let m = fetch(GoalModel.self, #Predicate { $0.id == target }).first {
            m.createdAt = goal.createdAt
            m.payload = try encode(goal)
        } else {
            context.insert(GoalModel(id: goal.id, createdAt: goal.createdAt, payload: try encode(goal)))
        }
        try save()
    }

    func deleteGoal(id: UUID) throws {
        let target = id
        for m in fetch(GoalModel.self, #Predicate { $0.id == target }) { context.delete(m) }
        try save()
    }

    private static let settingsKey = "user"

    func settings() -> UserSettings {
        let key = Self.settingsKey
        return fetch(SettingsModel.self, #Predicate { $0.key == key }).first
            .flatMap { decode(UserSettings.self, $0.payload) } ?? .default
    }

    func saveSettings(_ settings: UserSettings) throws {
        let key = Self.settingsKey
        let payload = try encode(settings)
        if let m = fetch(SettingsModel.self, #Predicate { $0.key == key }).first {
            m.payload = payload
        } else {
            context.insert(SettingsModel(key: key, payload: payload))
        }
        try save()
    }

    // MARK: - Snapshot / merge

    func snapshot() -> GymDatabase {
        GymDatabase(
            schemaVersion: GymSchema.currentVersion,
            exercises: exercises(),
            routines: routines(),
            routineExercises: fetch(RoutineExerciseModel.self).compactMap { decode(RoutineExercise.self, $0.payload) }.sorted { $0.id.uuidString < $1.id.uuidString },
            schedule: scheduleEntries(),
            sessions: sessions(),
            exerciseLogs: fetch(ExerciseLogModel.self).compactMap { decode(ExerciseLog.self, $0.payload) }.sorted { $0.id.uuidString < $1.id.uuidString },
            setLogs: fetch(SetLogModel.self).compactMap { decode(SetLog.self, $0.payload) }.sorted { $0.id.uuidString < $1.id.uuidString },
            decisions: fetch(DecisionModel.self).compactMap { decode(RecommendationDecision.self, $0.payload) }.sorted { $0.id.uuidString < $1.id.uuidString },
            comparabilityLinks: comparabilityLinks(),
            goals: goals(),
            settings: settings()
        )
    }

    /// Inserts only records whose id does not exist (never overwrites: an old backup can never undo
    /// newer history). All-or-nothing: staged in the context, saved once, rolled back on error.
    func merge(_ database: GymDatabase, includeSettings: Bool) throws {
        batching = true
        defer { batching = false }
        do {
            for e in database.exercises where exerciseModel(e.id) == nil { try upsertExercise(e) }
            for r in database.routines where routineModel(r.id) == nil { try upsertRoutine(r) }
            for r in database.routineExercises where routineExerciseModel(r.id) == nil { try upsertRoutineExercise(r) }
            let scheduleIds = Set(scheduleEntries().map(\.id))
            for s in database.schedule where !scheduleIds.contains(s.id) { try insertScheduleEntry(s) }
            for s in database.sessions where sessionModel(s.id) == nil { try upsertSession(s) }
            for l in database.exerciseLogs where logModel(l.id) == nil { try upsertExerciseLog(l) }
            for s in database.setLogs where setModel(s.id) == nil { try upsertSetLog(s) }
            for d in database.decisions where decision(exerciseLogId: d.exerciseLogId) == nil { try upsertDecision(d) }
            let linkIds = Set(comparabilityLinks().map(\.id))
            for l in database.comparabilityLinks where !linkIds.contains(l.id) { try insertComparabilityLink(l) }
            let goalIds = Set(goals().map(\.id))
            for g in database.goals where !goalIds.contains(g.id) { try upsertGoal(g) }
            if includeSettings { try saveSettings(database.settings) }
            batching = false
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Every stored payload must decode and every fetch must succeed; otherwise an export would be
    /// silently incomplete.
    func validateIntegrity() throws {
        readFailures = []
        let counts = [
            (fetch(ExerciseModel.self).count, exercises().count),
            (fetch(SessionModel.self).count, sessions().count),
            (fetch(ExerciseLogModel.self).count, fetch(ExerciseLogModel.self).compactMap { decode(ExerciseLog.self, $0.payload) }.count),
            (fetch(SetLogModel.self).count, fetch(SetLogModel.self).compactMap { decode(SetLog.self, $0.payload) }.count),
            (fetch(DecisionModel.self).count, fetch(DecisionModel.self).compactMap { decode(RecommendationDecision.self, $0.payload) }.count),
        ]
        if !readFailures.isEmpty || counts.contains(where: { $0.0 != $0.1 }) {
            throw GymStoreError.storage("Hay registros que no se pudieron leer (\(readFailures.prefix(3).joined(separator: "; "))). No se exportó nada para no generar una copia incompleta.")
        }
    }

    // MARK: - Batched reads

    func setLogs(exerciseLogIds: [UUID]) -> [UUID: [SetLog]] {
        let ids = exerciseLogIds
        var result: [UUID: [SetLog]] = [:]
        for model in fetch(SetLogModel.self, #Predicate { ids.contains($0.exerciseLogId) }) {
            if let set = decode(SetLog.self, model.payload) { result[set.exerciseLogId, default: []].append(set) }
        }
        for key in result.keys {
            result[key]?.sort { ($0.index, $0.id.uuidString) < ($1.index, $1.id.uuidString) }
        }
        return result
    }

    func sessions(ids: [UUID]) -> [UUID: WorkoutSession] {
        let wanted = ids
        var result: [UUID: WorkoutSession] = [:]
        for model in fetch(SessionModel.self, #Predicate { wanted.contains($0.id) }) {
            if let s = decode(WorkoutSession.self, model.payload) { result[s.id] = s }
        }
        return result
    }

    // MARK: - Helpers

    private var batching = false
    /// Read errors since the last integrity check (fetch failures or undecodable payloads).
    private(set) var readFailures: [String] = []
    private let logger = Logger(subsystem: "GymProgress", category: "persistence")

    private func save() throws {
        guard !batching else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw GymStoreError.storage(String(describing: error))
        }
    }

    private func fetch<M: PersistentModel>(_ type: M.Type, _ predicate: Predicate<M>? = nil) -> [M] {
        let descriptor = FetchDescriptor<M>(predicate: predicate)
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch \(String(describing: M.self), privacy: .public) failed: \(String(describing: error), privacy: .public)")
            readFailures.append("lectura de \(M.self)")
            return []
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Undecodable \(String(describing: T.self), privacy: .public): \(String(describing: error), privacy: .public)")
            readFailures.append("registro \(T.self) ilegible")
            return nil
        }
    }

    private func routine(from m: RoutineModel) -> RoutineTemplate {
        RoutineTemplate(id: m.id, name: m.name, sortOrder: m.sortOrder, notes: m.notes, isArchived: m.isArchived, createdAt: m.createdAt)
    }

    private func exerciseModel(_ id: UUID) -> ExerciseModel? {
        let target = id
        return fetch(ExerciseModel.self, #Predicate { $0.id == target }).first
    }

    private func routineModel(_ id: UUID) -> RoutineModel? {
        let target = id
        return fetch(RoutineModel.self, #Predicate { $0.id == target }).first
    }

    private func routineExerciseModel(_ id: UUID) -> RoutineExerciseModel? {
        let target = id
        return fetch(RoutineExerciseModel.self, #Predicate { $0.id == target }).first
    }

    private func sessionModel(_ id: UUID) -> SessionModel? {
        let target = id
        return fetch(SessionModel.self, #Predicate { $0.id == target }).first
    }

    private func logModel(_ id: UUID) -> ExerciseLogModel? {
        let target = id
        return fetch(ExerciseLogModel.self, #Predicate { $0.id == target }).first
    }

    private func setModel(_ id: UUID) -> SetLogModel? {
        let target = id
        return fetch(SetLogModel.self, #Predicate { $0.id == target }).first
    }
}
