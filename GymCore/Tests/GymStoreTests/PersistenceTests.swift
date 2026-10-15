import Foundation
import Testing
@testable import GymCore
@testable import GymStore

@MainActor
@Suite("Persistence and recommendation decisions")
struct PersistenceTests {

    // MARK: Section 2.D case 8 — full persistence side

    @Test("Case 8: modified decision persists across reload, is never overwritten, next rec uses actual performance")
    func case8_modifiedDecisionLifecycle() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])

        // Session 2: the engine recommends 62.5 × 8.
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        let opened = try store.workout.openExercise(logId: logId, now: SFx.day(3, minutes: 1))
        #expect(opened.recommendation.action == .increaseWeight)
        #expect(opened.recommendation.targetWeight == 62.5)
        #expect(opened.recommendation.targetReps == [8, 8, 8])

        // The user modifies the target to 61 kg.
        try store.workout.decide(logId: logId, choice: .modify(weight: 61, reps: [8, 8, 8]), now: SFx.day(3, minutes: 2))

        // Close and reopen the app.
        try store.reload()
        let decision = try #require(store.repo.decision(exerciseLogId: logId))
        #expect(decision.kind == .modified)
        #expect(decision.recommended.targetWeight == 62.5)
        #expect(decision.recommended.targetReps == [8, 8, 8])
        #expect(decision.finalWeight == 61)
        #expect(decision.finalReps == [8, 8, 8])
        #expect(decision.decidedAt == SFx.day(3, minutes: 2))
        #expect(store.workout.openSession()?.id == session.id)

        // Re-entering the screen later (and recomputing previews) never overwrites anything.
        let reopened = try store.workout.openExercise(logId: logId, now: SFx.day(3, minutes: 40))
        _ = store.workout.previewRecommendation(exerciseId: bench.id, now: SFx.day(3, minutes: 41))
        #expect(reopened.recommendation == opened.recommendation)
        #expect(reopened.decision == decision)
        #expect(reopened.sets.filter { $0.kind == .working }.allSatisfy { $0.weight == 61 && $0.targetReps == 8 })

        // A context change after deciding keeps decision and frozen recommendation.
        try store.workout.setContext(logId: logId, variantLabel: nil, equipmentLabel: nil, now: SFx.day(3, minutes: 42))
        #expect(store.repo.decision(exerciseLogId: logId) == decision)
        #expect(store.repo.exerciseLog(id: logId)?.frozenRecommendation == opened.recommendation)

        // The user actually does 61 × 10, 9, 9.
        for (set, reps) in zip(store.repo.setLogs(exerciseLogId: logId), [10, 9, 9]) {
            var s = set
            s.reps = reps
            s.rir = 2
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: SFx.day(3, minutes: 50))
        }
        try store.workout.finish(sessionId: session.id, now: SFx.day(3, minutes: 70))
        try store.reload()

        // Next session: computed from what was performed (61 kg), not from the manual target.
        let next = try #require(store.workout.previewRecommendation(exerciseId: bench.id, now: SFx.day(6)))
        #expect(next.lastPerformance?.workingLoad == 61)
        #expect(next.action == .increaseReps)
        #expect(next.targetWeight == 61)
        #expect(next.targetReps == [11, 10, 10])
        #expect(store.repo.decision(exerciseLogId: logId) == decision)
    }

    @Test("Accepted, modified and ignored decisions persist and survive recomputation", arguments: [
        DecisionChoice.accept,
        DecisionChoice.modify(weight: 61, reps: [10, 9, 8]),
        DecisionChoice.ignore,
    ])
    func decisionKindsPersist(choice: DecisionChoice) throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])

        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        let first = try store.workout.openExercise(logId: logId, now: SFx.day(3, minutes: 1))
        let decision = try store.workout.decide(logId: logId, choice: choice, now: SFx.day(3, minutes: 2))

        // More history appears elsewhere (e.g. an import) and the app relaunches.
        try store.reload()
        let again = try store.workout.openExercise(logId: logId, now: SFx.day(4))
        #expect(again.decision == decision)
        #expect(again.recommendation == first.recommendation)

        let working = again.sets.filter { $0.kind == .working }
        switch choice {
        case .accept:
            #expect(decision.kind == .accepted)
            #expect(working.allSatisfy { $0.weight == 62.5 && $0.targetReps == 8 })
        case .modify:
            #expect(decision.kind == .modified)
            #expect(working.map(\.weight) == [61, 61, 61])
            #expect(working.map(\.targetReps) == [10, 9, 8])
        case .ignore:
            #expect(decision.kind == .ignored)
            #expect(decision.finalWeight == nil)
            #expect(working.allSatisfy { $0.weight == nil && $0.targetReps == nil })
        }
    }

    @Test("Changing one's mind updates the same decision and keeps the originally shown recommendation")
    func changeDecision() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id

        let accepted = try store.workout.decide(logId: logId, choice: .accept, now: SFx.day(3, minutes: 1))
        let ignored = try store.workout.decide(logId: logId, choice: .ignore, now: SFx.day(3, minutes: 2))
        #expect(accepted.id == ignored.id)
        #expect(ignored.recommended == accepted.recommended)
        #expect(ignored.kind == .ignored)
        // Switching to "ignore" removes the pre-filled load it had put there.
        #expect(store.repo.setLogs(exerciseLogId: logId).allSatisfy { $0.weight == nil && $0.targetReps == nil })
    }

    @Test("Before any decision, changing the machine recomputes for the new context (no false comparison)")
    func contextChangeBeforeDecision() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        #expect(try store.workout.openExercise(logId: logId, now: SFx.day(3)).recommendation.action == .increaseWeight)

        try store.workout.setContext(logId: logId, variantLabel: nil, equipmentLabel: "Smith", now: SFx.day(3, minutes: 1))
        let state = try store.workout.openExercise(logId: logId, now: SFx.day(3, minutes: 2))
        #expect(state.recommendation.reason == .noComparableHistoryInContext)
        #expect(state.recommendation.nonEquivalentReference?.workingLoad == 60)

        // The user explicitly treats both contexts as equivalent → later recommendations compare them.
        try store.workout.linkContexts(state.log.context, ComparabilityContext(exerciseId: bench.id, loadMode: .total), now: SFx.day(3, minutes: 3))
        #expect(store.workout.previewRecommendation(exerciseId: bench.id, now: SFx.day(3, minutes: 4))?.action == .increaseWeight)
    }

    // MARK: Session recovery

    @Test("Interrupted session is recovered with sets, decisions and pause state")
    func recoverInterruptedSession() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        _ = try store.workout.openExercise(logId: logId, now: SFx.day(0, minutes: 1))
        try store.workout.decide(logId: logId, choice: .modify(weight: 40, reps: [10, 10, 10]), now: SFx.day(0, minutes: 2))
        let first = store.repo.setLogs(exerciseLogId: logId)[0]
        try store.workout.completeSet(setId: first.id, now: SFx.day(0, minutes: 5))
        try store.workout.pause(sessionId: session.id, now: SFx.day(0, minutes: 10))

        // Crash: nothing else is saved explicitly.
        try store.reload()
        let recovered = try #require(store.workout.openSession())
        #expect(recovered.id == session.id)
        #expect(recovered.status == .paused)
        let sets = store.repo.setLogs(exerciseLogId: logId)
        #expect(sets[0].status == .completed)
        #expect(sets[0].weight == 40)
        #expect(sets[0].reps == 10) // one-tap completion used the visible target
        #expect(store.repo.decision(exerciseLogId: logId)?.kind == .modified)

        try store.workout.resume(sessionId: session.id, now: SFx.day(0, minutes: 25))
        let resumed = try #require(store.repo.session(id: session.id))
        // 30 minutes elapsed, 15 paused.
        #expect(resumed.elapsed(at: SFx.day(0, minutes: 30)) == 15 * 60)
    }

    @Test("Only one open session at a time")
    func singleOpenSession() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        #expect(throws: GymStoreError.sessionAlreadyOpen) {
            try store.workout.startSession(routineId: routine.id, now: SFx.day(0, minutes: 1))
        }
    }

    // MARK: Sets

    @Test("Completing a set: one tap, execution order recorded, invalid values rejected")
    func completeSetRules() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try store.routines.createRoutine(name: "R", now: SFx.day(0))
        let row = try store.catalog.createCustomExercise(name: "Remo", measurement: .weightReps, equipment: .cable, loadMode: .total, primaryMuscles: [.upperBack])
        try store.routines.addExercise(routineId: routine.id, exerciseId: bench.id)
        try store.routines.addExercise(routineId: routine.id, exerciseId: row.id)
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let logs = store.repo.exerciseLogs(sessionId: session.id)

        // Missing weight → refused.
        let rowSet = store.repo.setLogs(exerciseLogId: logs[1].id)[0]
        #expect(throws: GymStoreError.missingValues) { try store.workout.completeSet(setId: rowSet.id, now: SFx.day(0)) }

        // Negative weight → refused.
        var bad = rowSet
        bad.weight = -5
        bad.reps = 10
        #expect(throws: GymStoreError.self) { try store.workout.updateSet(bad) }

        // The second planned exercise is done first: real order is recorded.
        var ok = rowSet
        ok.weight = 50
        ok.reps = 12
        try store.workout.updateSet(ok)
        try store.workout.completeSet(setId: ok.id, now: SFx.day(0, minutes: 5))
        var b = store.repo.setLogs(exerciseLogId: logs[0].id)[0]
        b.weight = 60
        b.reps = 8
        try store.workout.updateSet(b)
        try store.workout.completeSet(setId: b.id, now: SFx.day(0, minutes: 10))
        #expect(store.repo.exerciseLog(id: logs[1].id)?.executionOrder == 0)
        #expect(store.repo.exerciseLog(id: logs[0].id)?.executionOrder == 1)

        // Weights typed with a comma are parsed and normalized.
        var comma = store.repo.setLogs(exerciseLogId: logs[0].id)[1]
        comma.weight = WeightParser.parse("62,5")
        comma.reps = 8
        try store.workout.updateSet(comma)
        #expect(store.repo.setLog(id: comma.id)?.weight == 62.5)
    }

    @Test("Copy previous loads with one tap (ignore path)")
    func copyPreviousLoads() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2])
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        try store.workout.decide(logId: logId, choice: .ignore, now: SFx.day(3))
        try store.workout.copyPreviousLoads(logId: logId, now: SFx.day(3, minutes: 1))
        let sets = store.repo.setLogs(exerciseLogId: logId)
        #expect(sets.map(\.weight) == [60, 60, 60])
        #expect(sets.map(\.targetReps) == [12, 11, 10])
    }

    @Test("Session-only changes never touch the routine template")
    func sessionOnlyChanges() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let curl = try store.catalog.createCustomExercise(name: "Curl", measurement: .weightReps, equipment: .dumbbell, loadMode: .perSide, primaryMuscles: [.biceps])
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let added = try store.workout.addExercise(sessionId: session.id, exerciseId: curl.id, now: SFx.day(0))
        let benchLog = store.repo.exerciseLogs(sessionId: session.id)[0]
        try store.workout.moveExercises(sessionId: session.id, orderedLogIds: [added.id, benchLog.id])
        #expect(store.repo.exerciseLogs(sessionId: session.id).map(\.exerciseId) == [curl.id, bench.id])
        try store.workout.removeExercise(logId: benchLog.id)
        #expect(store.repo.routineExercises(routineId: routine.id).map(\.exerciseId) == [bench.id])
    }

    // MARK: Immutable history

    @Test("Archiving/deleting routines and exercises never alters past sessions")
    func archiveAndDelete() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let (session, log) = try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10])

        #expect(throws: GymStoreError.hasHistory) { try store.routines.deleteRoutine(id: routine.id) }
        #expect(throws: GymStoreError.hasHistory) { try store.catalog.deleteExercise(id: bench.id) }

        try store.routines.setArchived(routineId: routine.id, true)
        try store.catalog.setArchived(exerciseId: bench.id, true)
        var renamed = try #require(store.repo.exercise(id: bench.id))
        renamed.name = "Otro nombre"
        try store.catalog.updateExercise(renamed)
        var r = try #require(store.repo.routine(id: routine.id))
        r.name = "Rutina renombrada"
        try store.routines.updateRoutine(r)

        try store.reload()
        #expect(store.repo.session(id: session.id)?.routineNameSnapshot == "Torso A")
        #expect(store.repo.exerciseLog(id: log.id)?.snapshot.name == "Press de banca")
        #expect(store.repo.setLogs(exerciseLogId: log.id).map(\.reps) == [10, 10, 10])
        #expect(store.history.exerciseHistory(exerciseId: bench.id).count == 1)

        // Without history, a real delete is allowed.
        let unused = try store.catalog.createCustomExercise(name: "Sin uso", measurement: .weightReps, equipment: .machine, loadMode: .total, primaryMuscles: [.quads])
        try store.catalog.deleteExercise(id: unused.id)
        #expect(store.repo.exercise(id: unused.id) == nil)
    }

    @Test("Editing the template or the ProgressionConfig never rewrites log snapshots")
    func configEditsDoNotRewriteHistory() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let (_, log) = try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])
        let frozen = log.frozenRecommendation

        try store.catalog.updateProgression(exerciseId: bench.id, config: ProgressionConfig(targetSets: 5, repMin: 3, repMax: 5, targetRIR: 1, increment: 5))
        var item = store.repo.routineExercises(routineId: routine.id)[0]
        item.progressionOverride = ProgressionConfig(targetSets: 4, repMin: 6, repMax: 8)
        try store.routines.updateRoutineExercise(item)

        try store.reload()
        let after = try #require(store.repo.exerciseLog(id: log.id))
        #expect(after.configSnapshot.targetSets == 3)
        #expect(after.configSnapshot.repMax == 12)
        #expect(after.configSnapshot.increment == 2.5)
        #expect(after.frozenRecommendation == frozen)

        // The new config applies to future sessions only.
        let next = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        #expect(store.repo.exerciseLogs(sessionId: next.id)[0].configSnapshot.targetSets == 4)
        #expect(store.repo.setLogs(exerciseLogId: store.repo.exerciseLogs(sessionId: next.id)[0].id).count == 4)
    }

    // MARK: Export / import / schema

    @Test("Export → import into an empty store: identical; importing twice never duplicates")
    func exportImportRoundTrip() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], choice: .accept)
        try SFx.performSession(store, routineId: routine.id, day: 3, weight: 62.5, reps: [8, 8, 8], choice: .modify(weight: 62.5, reps: [9, 9, 9]))
        try store.workout.linkContexts(ComparabilityContext(exerciseId: bench.id, equipmentLabel: "A", loadMode: .total), ComparabilityContext(exerciseId: bench.id, loadMode: .total), now: SFx.day(4))
        let data = try store.export.exportJSON(now: SFx.day(5))

        let target = try TestStore()
        let first = try target.export.importJSON(data)
        #expect(first.updated == 0)
        #expect(first.inserted > 0)
        var a = store.repo.snapshot(); a.exportedAt = nil
        var b = target.repo.snapshot(); b.exportedAt = nil
        #expect(a == b)
        #expect(b.decisions.count == 2)
        #expect(b.comparabilityLinks.count == 1)

        let second = try target.export.importJSON(data)
        #expect(second.inserted == 0)
        #expect(second.updated == 0)
        #expect(target.repo.snapshot().setLogs.count == a.setLogs.count)

        try target.reload()
        var c = target.repo.snapshot(); c.exportedAt = nil
        #expect(c == a)
    }

    @Test("Import validation: unknown schema version and broken references are rejected without changes")
    func importValidation() throws {
        let store = try TestStore()
        var db = GymDatabase()
        db.schemaVersion = GymSchema.currentVersion + 1
        #expect(throws: GymStoreError.unsupportedSchemaVersion(GymSchema.currentVersion + 1)) {
            try store.export.importJSON(try GymJSON.encoder.encode(db))
        }
        var orphan = GymDatabase()
        orphan.setLogs = [SetLog(exerciseLogId: UUID(), index: 0)]
        #expect(throws: GymStoreError.self) { try store.export.importJSON(try GymJSON.encoder.encode(orphan)) }
        #expect(throws: GymStoreError.self) { try store.export.importJSON(Data("no es json".utf8)) }
        #expect(store.repo.snapshot() == GymDatabase())
    }

    @Test("Schema v1 documents decode (migration plan anchor)")
    func schemaV1Decodes() throws {
        let json = """
        {"schemaVersion":1,"exercises":[],"routines":[],"routineExercises":[],"schedule":[],"sessions":[],
         "exerciseLogs":[],"setLogs":[],"decisions":[],"comparabilityLinks":[],"goals":[],
         "settings":{"weightUnit":"kg","firstWeekday":2,"defaultRestSeconds":120,"theme":"dark","weeklyGoal":3,
           "streakMode":"weeklyPlan","maxGapDays":2,"indirectSetFactor":0.5,"oneRepMax":{"formula":"epley","maxReps":10},
           "minSetsForValidSession":3,"keepScreenOn":true,"restNotifications":true}}
        """
        let db = try GymJSON.decoder.decode(GymDatabase.self, from: Data(json.utf8))
        #expect(db.schemaVersion == 1)
        #expect(db.settings.bodyweightKg == nil)
    }

    @Test("CSV export: one row per set, machine-readable numbers")
    func csvExport() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 62.5, reps: [8, 8, 8], rir: [2, 2, 2])
        let lines = store.export.exportSetsCSV().split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[1].contains(",62.5,8,"))
        #expect(lines[1].contains("Press de banca"))
    }

    // MARK: Catalog

    @Test("Bundled catalog: 80–120 exercises, stable unique ids, idempotent seeding that keeps user edits")
    func catalogSeeding() throws {
        let catalog = try ExerciseCatalog.bundled()
        #expect((80...120).contains(catalog.exercises.count))
        #expect(Set(catalog.exercises.map(\.uuid)).count == catalog.exercises.count)
        #expect(Set(catalog.exercises.map(\.catalogId)).count == catalog.exercises.count)
        #expect(catalog.exercises.allSatisfy { !$0.primary.isEmpty && $0.increment > 0 })

        let store = try TestStore()
        let custom = try store.catalog.createCustomExercise(name: "Mi ejercicio", measurement: .weightReps, equipment: .other, loadMode: .total, primaryMuscles: [.abs])
        let first = try store.catalog.seed(catalog)
        #expect(first.inserted == catalog.exercises.count)

        let benchId = try #require(catalog.exercises.first { $0.catalogId == "barbell-bench-press" }?.uuid)
        try store.catalog.updateProgression(exerciseId: benchId, config: ProgressionConfig(targetSets: 5, repMin: 3, repMax: 5, increment: 1.25))
        let again = try store.catalog.seed(catalog)
        #expect(again.inserted == 0)
        #expect(store.repo.exercise(id: benchId)?.progression.increment == 1.25)
        #expect(store.repo.exercise(id: custom.id) != nil)

        let preset = try #require(RoutinePreset.all.first { $0.id == "full-body-a" })
        let routine = try store.routines.createFromPreset(preset, now: SFx.day(0))
        #expect(store.repo.routineExercises(routineId: routine.id).count == preset.exercises.count)
        let plank = store.repo.routineExercises(routineId: routine.id).last!
        #expect(plank.progressionOverride?.secondsMax == 60)
        // Every preset references existing catalog ids.
        let ids = Set(catalog.exercises.map(\.catalogId))
        #expect(RoutinePreset.all.allSatisfy { $0.exercises.allSatisfy { ids.contains($0.catalogId) } })
    }
}
