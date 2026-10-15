import Foundation
import Testing
@testable import GymCore
@testable import GymStore

/// Regression tests for the findings of the stage 2–3 independent review.
@MainActor
@Suite("Stage 2–3 review regressions")
struct ReviewRegressionTests {

    @Test("C1: importing an older backup never undoes a newer finished workout")
    func olderBackupDoesNotOverwrite() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let backup = try store.export.exportJSON(now: SFx.day(0, minutes: 1)) // taken mid-workout

        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        try store.workout.decide(logId: logId, choice: .modify(weight: 50, reps: [10, 10, 10]), now: SFx.day(0, minutes: 2))
        for set in store.repo.setLogs(exerciseLogId: logId) {
            try store.workout.completeSet(setId: set.id, now: SFx.day(0, minutes: 5))
        }
        try store.workout.finish(sessionId: session.id, now: SFx.day(0, minutes: 50))
        let before = store.repo.snapshot()

        let summary = try store.export.importJSON(backup)
        #expect(summary.inserted == 0)
        #expect(summary.conflicts > 0)
        #expect(store.repo.snapshot() == before)
        #expect(store.repo.session(id: session.id)?.status == .completed)
        #expect(store.history.exerciseHistory(exerciseId: bench.id).count == 1)
    }

    @Test("C1: a backup with another open workout is refused while one is open locally")
    func noSecondOpenSession() throws {
        let other = try TestStore()
        let benchB = try SFx.bench(in: other)
        let routineB = try SFx.routine(with: benchB, in: other)
        try other.workout.startSession(routineId: routineB.id, now: SFx.day(0))
        let data = try other.export.exportJSON(now: SFx.day(0, minutes: 1))

        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try store.workout.startSession(routineId: routine.id, now: SFx.day(1))
        let before = store.repo.snapshot()
        #expect(throws: GymStoreError.self) { try store.export.importJSON(data) }
        #expect(store.repo.snapshot() == before)
        #expect(store.repo.sessions().filter(\.isOpen).count == 1)
    }

    @Test("C1: restoring into an empty store brings settings; into a used store, local settings stay")
    func settingsOnlyIntoEmptyStore() throws {
        let source = try TestStore()
        var settings = UserSettings.default
        settings.weeklyGoal = 5
        try source.repo.saveSettings(settings)
        let bench = try SFx.bench(in: source)
        _ = try SFx.routine(with: bench, in: source)
        let data = try source.export.exportJSON(now: SFx.day(0))

        let empty = try TestStore()
        try empty.export.importJSON(data)
        #expect(empty.repo.settings().weeklyGoal == 5)

        let used = try TestStore()
        _ = try SFx.routine(with: try SFx.bench(in: used), in: used)
        try used.export.importJSON(data)
        #expect(used.repo.settings().weeklyGoal == UserSettings.default.weeklyGoal)
    }

    @Test("M1: switching machine and treating it as equivalent compares today's card with the old machine")
    func switchContextTreatingAsEquivalent() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        // History on "Máquina A".
        let s0 = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let log0 = store.repo.exerciseLogs(sessionId: s0.id)[0]
        try store.workout.setContext(logId: log0.id, variantLabel: nil, equipmentLabel: "Máquina A", now: SFx.day(0))
        for set in store.repo.setLogs(exerciseLogId: log0.id) {
            var s = set; s.weight = 60; s.reps = 12; s.rir = 2
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: SFx.day(0, minutes: 5))
        }
        try store.workout.finish(sessionId: s0.id, now: SFx.day(0, minutes: 40))

        // Today the default context is Máquina A; the user switches to B and says it is equivalent.
        let s1 = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let log1 = store.repo.exerciseLogs(sessionId: s1.id)[0]
        #expect(log1.equipmentLabel == "Máquina A")
        _ = try store.workout.openExercise(logId: log1.id, now: SFx.day(3))
        try store.workout.switchContextTreatingAsEquivalent(logId: log1.id, variantLabel: nil, equipmentLabel: "Máquina B", now: SFx.day(3, minutes: 1))
        let card = try store.workout.openExercise(logId: log1.id, now: SFx.day(3, minutes: 2))
        #expect(card.log.equipmentLabel == "Máquina B")
        #expect(card.recommendation.action == .increaseWeight)
        #expect(card.recommendation.targetWeight == 62.5)
    }

    @Test("Minor 3: decisions and structural set changes are refused once the session is finished")
    func finishedSessionIsImmutableStructurally() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let (_, log) = try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [11, 10])
        let sets = store.repo.setLogs(exerciseLogId: log.id)
        #expect(throws: GymStoreError.sessionNotOpen) { try store.workout.removeSet(setId: sets[0].id) }
        #expect(throws: GymStoreError.sessionNotOpen) { try store.workout.completeSet(setId: sets[2].id, now: SFx.day(1)) }
        #expect(throws: GymStoreError.sessionNotOpen) { try store.workout.decide(logId: log.id, choice: .accept, now: SFx.day(1)) }
        #expect(throws: GymStoreError.sessionNotOpen) { try store.workout.addSet(logId: log.id) }
        #expect(store.repo.setLogs(exerciseLogId: log.id).map(\.index) == [0, 1, 2])
    }

    @Test("Minor 4: copying loads from a non-equivalent context needs an explicit choice")
    func copyFromNonEquivalentNeedsExplicitChoice() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12])
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        try store.workout.setContext(logId: logId, variantLabel: nil, equipmentLabel: "Smith", now: SFx.day(3))
        #expect(throws: GymStoreError.self) { try store.workout.copyPreviousLoads(logId: logId, now: SFx.day(3)) }
        #expect(store.repo.setLogs(exerciseLogId: logId).allSatisfy { $0.weight == nil })
        try store.workout.copyPreviousLoads(logId: logId, allowNonEquivalent: true, now: SFx.day(3))
        #expect(store.repo.setLogs(exerciseLogId: logId).allSatisfy { $0.weight == 60 })
    }

    @Test("Minor 5: initial target is stored in the routine override when one exists, and previews use it")
    func initialTargetAndPreviewUseRoutineOverride() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try store.routines.createRoutine(name: "R", now: SFx.day(0))
        try store.routines.addExercise(routineId: routine.id, exerciseId: bench.id, override: ProgressionConfig(targetSets: 4, repMin: 5, repMax: 8, targetRIR: 1, increment: 5))
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        #expect(try store.workout.openExercise(logId: logId, now: SFx.day(0)).recommendation.reason == .noComparableHistory)

        let decision = try store.workout.setInitialTarget(logId: logId, weight: 70, reps: [5, 5, 5, 5], now: SFx.day(0, minutes: 1))
        #expect(decision.kind == .modified)
        #expect(store.repo.routineExercises(routineId: routine.id)[0].progressionOverride?.initialWeight == 70)
        #expect(store.repo.exercise(id: bench.id)?.progression.initialWeight == nil)

        for (set, reps) in zip(store.repo.setLogs(exerciseLogId: logId), [8, 8, 8, 8]) {
            var s = set; s.reps = reps; s.rir = 1
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: SFx.day(0, minutes: 10))
        }
        try store.workout.finish(sessionId: session.id, now: SFx.day(0, minutes: 50))
        // The history screen preview uses the routine's criteria (4 × 5–8, +5 kg), like the next card.
        let preview = try #require(store.workout.previewRecommendation(exerciseId: bench.id, now: SFx.day(2)))
        #expect(preview.target.sets == 4)
        #expect(preview.targetWeight == 75)
        #expect(preview.targetReps == [5, 5, 5, 5])
    }

    @Test("Minor 8: merge never rewrites existing schedule entries (append-only)")
    func mergeKeepsScheduleAppendOnly() throws {
        let store = try TestStore()
        let entry = ScheduleEntry(id: SFx.fixedId, weekday: 2, routineId: nil, validFrom: SFx.day(0), createdAt: SFx.day(0))
        try store.repo.insertScheduleEntry(entry)
        var altered = entry
        altered.weekday = 5
        var db = GymDatabase()
        db.schedule = [altered]
        try store.repo.merge(db, includeSettings: false)
        #expect(store.repo.scheduleEntries() == [entry])
    }
}

extension SFx {
    static let fixedId = UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!
}
