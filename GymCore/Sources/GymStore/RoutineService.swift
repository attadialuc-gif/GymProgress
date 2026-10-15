import Foundation
import GymCore

/// Routine templates. Editing a template never alters past sessions (logs keep snapshots).
@MainActor
public struct RoutineService {
    public let repository: any GymRepository

    public init(repository: any GymRepository) {
        self.repository = repository
    }

    @discardableResult
    public func createRoutine(name: String, notes: String = "", now: Date) throws -> RoutineTemplate {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GymStoreError.invalidValue("El nombre no puede estar vacío.") }
        let order = (repository.routines().map(\.sortOrder).max() ?? -1) + 1
        let routine = RoutineTemplate(name: clean, sortOrder: order, notes: notes, createdAt: now)
        try repository.upsertRoutine(routine)
        return routine
    }

    public func updateRoutine(_ routine: RoutineTemplate) throws {
        guard repository.routine(id: routine.id) != nil else { throw GymStoreError.notFound("routine") }
        guard !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GymStoreError.invalidValue("El nombre no puede estar vacío.") }
        try repository.upsertRoutine(routine)
    }

    @discardableResult
    public func duplicateRoutine(id: UUID, now: Date) throws -> RoutineTemplate {
        guard let source = repository.routine(id: id) else { throw GymStoreError.notFound("routine") }
        let copy = try createRoutine(name: "\(source.name) (copia)", notes: source.notes, now: now)
        for item in repository.routineExercises(routineId: id) {
            var dup = item
            dup.id = UUID()
            dup.routineId = copy.id
            try repository.upsertRoutineExercise(dup)
        }
        return copy
    }

    public func setArchived(routineId: UUID, _ archived: Bool) throws {
        guard var routine = repository.routine(id: routineId) else { throw GymStoreError.notFound("routine") }
        routine.isArchived = archived
        try repository.upsertRoutine(routine)
    }

    /// Hard delete only when no session used the routine; otherwise archive instead.
    public func deleteRoutine(id: UUID) throws {
        try repository.deleteRoutine(id: id)
    }

    public func reorderRoutines(_ orderedIds: [UUID]) throws {
        for (i, id) in orderedIds.enumerated() {
            guard var routine = repository.routine(id: id), routine.sortOrder != i else { continue }
            routine.sortOrder = i
            try repository.upsertRoutine(routine)
        }
    }

    // MARK: Exercises in a routine

    @discardableResult
    public func addExercise(routineId: UUID, exerciseId: UUID, override: ProgressionConfig? = nil, restSeconds: Int? = nil, notes: String = "") throws -> RoutineExercise {
        guard repository.routine(id: routineId) != nil else { throw GymStoreError.notFound("routine") }
        guard repository.exercise(id: exerciseId) != nil else { throw GymStoreError.notFound("exercise") }
        let order = (repository.routineExercises(routineId: routineId).map(\.sortOrder).max() ?? -1) + 1
        let item = RoutineExercise(routineId: routineId, exerciseId: exerciseId, sortOrder: order, restSeconds: restSeconds, notes: notes, progressionOverride: override?.sanitized())
        try repository.upsertRoutineExercise(item)
        return item
    }

    public func updateRoutineExercise(_ item: RoutineExercise) throws {
        guard repository.routineExercise(id: item.id) != nil else { throw GymStoreError.notFound("routineExercise") }
        var clean = item
        clean.progressionOverride = item.progressionOverride?.sanitized()
        try repository.upsertRoutineExercise(clean)
    }

    public func removeRoutineExercise(id: UUID) throws {
        try repository.deleteRoutineExercise(id: id)
    }

    @discardableResult
    public func duplicateRoutineExercise(id: UUID) throws -> RoutineExercise {
        guard let item = repository.routineExercise(id: id) else { throw GymStoreError.notFound("routineExercise") }
        var dup = item
        dup.id = UUID()
        dup.sortOrder = item.sortOrder + 1
        // Shift the following items down to make room right after the original.
        for other in repository.routineExercises(routineId: item.routineId) where other.sortOrder > item.sortOrder {
            var moved = other
            moved.sortOrder += 1
            try repository.upsertRoutineExercise(moved)
        }
        try repository.upsertRoutineExercise(dup)
        return dup
    }

    public func moveExercises(routineId: UUID, orderedIds: [UUID]) throws {
        for (i, id) in orderedIds.enumerated() {
            guard var item = repository.routineExercise(id: id), item.routineId == routineId, item.sortOrder != i else { continue }
            item.sortOrder = i
            try repository.upsertRoutineExercise(item)
        }
    }

    /// Groups exercises as a superset / biset (`nil` ungroups).
    public func setSuperset(ids: [UUID], group: Int?) throws {
        for id in ids {
            guard var item = repository.routineExercise(id: id) else { continue }
            item.supersetGroup = group
            try repository.upsertRoutineExercise(item)
        }
    }

    public func effectiveConfig(for item: RoutineExercise) -> ProgressionConfig? {
        if let override = item.progressionOverride { return override }
        return repository.exercise(id: item.exerciseId)?.progression
    }

    /// Creates an editable routine from a preset. Exercises missing from the catalog are skipped.
    @discardableResult
    public func createFromPreset(_ preset: RoutinePreset, now: Date) throws -> RoutineTemplate {
        let byCatalogId = Dictionary(repository.exercises().compactMap { e in e.catalogId.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        let routine = try createRoutine(name: preset.name, notes: preset.notes, now: now)
        for entry in preset.exercises {
            guard let exercise = byCatalogId[entry.catalogId] else { continue }
            var config = exercise.progression
            config.targetSets = entry.sets
            if exercise.measurement == .duration {
                config.secondsMin = entry.repMin
                config.secondsMax = entry.repMax
            } else {
                config.repMin = entry.repMin
                config.repMax = entry.repMax
            }
            try addExercise(routineId: routine.id, exerciseId: exercise.id, override: config, restSeconds: entry.restSeconds)
        }
        return routine
    }
}

/// Exercise library management. The catalog can be updated without losing user exercises or the
/// user's edits to catalog exercises' progression criteria.
@MainActor
public struct ExerciseCatalogService {
    public let repository: any GymRepository

    public init(repository: any GymRepository) {
        self.repository = repository
    }

    @discardableResult
    public func createCustomExercise(
        name: String,
        measurement: MeasurementType,
        equipment: Equipment,
        loadMode: LoadMode,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleInvolvement] = [],
        increment: Double = 2.5,
        availableWeights: [Double]? = nil,
        progression: ProgressionConfig? = nil
    ) throws -> Exercise {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GymStoreError.invalidValue("El nombre no puede estar vacío.") }
        var config = progression ?? ProgressionConfig(increment: increment, availableWeights: availableWeights)
        config.increment = increment
        config.availableWeights = availableWeights
        let exercise = Exercise(
            name: clean,
            measurement: measurement,
            equipment: equipment,
            loadMode: loadMode,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            defaultIncrement: increment,
            availableWeights: availableWeights,
            progression: config.sanitized(),
            isCustom: true
        )
        try repository.upsertExercise(exercise)
        return exercise
    }

    /// Catalog edits never touch past logs (they hold snapshots).
    public func updateExercise(_ exercise: Exercise) throws {
        guard repository.exercise(id: exercise.id) != nil else { throw GymStoreError.notFound("exercise") }
        var clean = exercise
        clean.progression = exercise.progression.sanitized()
        try repository.upsertExercise(clean)
    }

    public func updateProgression(exerciseId: UUID, config: ProgressionConfig) throws {
        guard var exercise = repository.exercise(id: exerciseId) else { throw GymStoreError.notFound("exercise") }
        exercise.progression = config.sanitized()
        try repository.upsertExercise(exercise)
    }

    public func setArchived(exerciseId: UUID, _ archived: Bool) throws {
        guard var exercise = repository.exercise(id: exerciseId) else { throw GymStoreError.notFound("exercise") }
        exercise.isArchived = archived
        try repository.upsertExercise(exercise)
    }

    /// Hard delete only without history (throws `hasHistory`; archive instead).
    public func deleteExercise(id: UUID) throws {
        try repository.deleteExercise(id: id)
    }

    /// Idempotent catalog seeding/update. New entries are inserted; existing catalog exercises get
    /// catalog fields refreshed (name, muscles, equipment) while the user's progression edits and
    /// archive flag are preserved. Custom exercises are never touched.
    @discardableResult
    public func seed(_ catalog: ExerciseCatalog) throws -> (inserted: Int, updated: Int) {
        var inserted = 0
        var updated = 0
        for entry in catalog.exercises {
            if var existing = repository.exercise(id: entry.uuid) {
                guard !existing.isCustom else { continue }
                let fresh = entry.makeExercise()
                if existing.name != fresh.name || existing.primaryMuscles != fresh.primaryMuscles
                    || existing.secondaryMuscles != fresh.secondaryMuscles || existing.equipment != fresh.equipment {
                    existing.name = fresh.name
                    existing.primaryMuscles = fresh.primaryMuscles
                    existing.secondaryMuscles = fresh.secondaryMuscles
                    existing.equipment = fresh.equipment
                    existing.catalogId = fresh.catalogId
                    try repository.upsertExercise(existing)
                    updated += 1
                }
            } else {
                try repository.upsertExercise(entry.makeExercise())
                inserted += 1
            }
        }
        return (inserted, updated)
    }
}
