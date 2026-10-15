import Foundation
import Testing
@testable import GymCore
@testable import GymStore

/// Regression tests for the findings of the stage 4–7 independent review.
@MainActor
@Suite("Stage 4–7 review regressions")
struct Stage4To7ReviewTests {

    func plannedStore() throws -> (TestStore, RoutineTemplate, ConsistencyService) {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let consistency = ConsistencyService(repository: store.repo, timeZone: SFx.tz)
        try consistency.setWeeklyPlan([2: routine.id, 4: routine.id, 6: routine.id], from: SFx.day(0), now: SFx.day(0))
        return (store, routine, consistency)
    }

    @Test("M1: a plan saved with a past 'from' date never rewrites past days")
    func pastFromIsClamped() throws {
        let (_, _, consistency) = try plannedStore()
        let before = consistency.week(containing: SFx.day(0), now: SFx.day(10)).map(\.status)
        #expect(before == [.missed, .rest, .missed, .rest, .missed, .rest, .rest])
        try consistency.setWeeklyPlan([:], from: SFx.day(0), now: SFx.day(10))
        #expect(consistency.week(containing: SFx.day(0), now: SFx.day(10)).map(\.status) == before)
        // From today on, the new (empty) plan applies.
        #expect(consistency.plannedRoutine(on: SFx.day(14)) == nil)
    }

    @Test("M6: the latest saved plan wins over a plan saved earlier for a later date")
    func latestDecisionWins() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let consistency = ConsistencyService(repository: store.repo, timeZone: SFx.tz)
        try consistency.setWeeklyPlan([2: routine.id], from: SFx.day(14), now: SFx.day(0))   // Mondays from day 14
        try consistency.setWeeklyPlan([4: routine.id], from: SFx.day(1), now: SFx.day(1))    // Wednesdays from day 1
        #expect(consistency.plannedRoutine(on: SFx.day(21)) == nil)            // Monday
        #expect(consistency.plannedRoutine(on: SFx.day(23)) == routine.id)     // Wednesday
        // The Wednesday plan starts on day 1 (Tuesday): Wednesday day 2 already planned.
        #expect(consistency.plannedRoutine(on: SFx.day(2)) == routine.id)
    }

    @Test("Home: next planned workout skips today once today's workout is done")
    func nextPlannedWorkout() throws {
        let (store, routine, consistency) = try plannedStore()
        #expect(consistency.nextPlannedWorkout(now: SFx.day(0))?.date == consistency.calendar.day(of: SFx.day(0)))
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10])
        let next = try #require(consistency.nextPlannedWorkout(now: SFx.day(0, minutes: 90)))
        #expect(next.date == consistency.calendar.day(of: SFx.day(2)))  // Wednesday
        // Rest day (Tuesday) → next planned day.
        #expect(consistency.nextPlannedWorkout(now: SFx.day(1))?.date == consistency.calendar.day(of: SFx.day(2)))
    }

    @Test("M2: records and charts never mix non-comparable machines; linked contexts are joined")
    func recordsPerContext() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10])
        // Next session on another machine with a much heavier load.
        let s = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let log = store.repo.exerciseLogs(sessionId: s.id)[0]
        try store.workout.setContext(logId: log.id, variantLabel: nil, equipmentLabel: "Máquina convergente", now: SFx.day(3))
        for set in store.repo.setLogs(exerciseLogId: log.id) {
            var x = set; x.weight = 100; x.reps = 10
            try store.workout.updateSet(x)
            try store.workout.completeSet(setId: x.id, now: SFx.day(3, minutes: 5))
        }
        try store.workout.finish(sessionId: s.id, now: SFx.day(3, minutes: 40))

        let stats = StatsService(repository: store.repo, timeZone: SFx.tz)
        let classes = stats.contextClasses(exerciseId: bench.id)
        #expect(classes.map(\.label) == ["Máquina convergente", "estándar"])
        #expect(stats.records(exerciseId: bench.id).maxWeight?.value == 100)                          // current = machine
        #expect(stats.records(exerciseId: bench.id, contextClass: classes[1]).maxWeight?.value == 60)
        #expect(stats.exerciseSeries(exerciseId: bench.id).map(\.workingLoad) == [100])
        #expect(stats.exerciseSeries(exerciseId: bench.id, contextClass: classes[1]).map(\.workingLoad) == [60])
        // A first session in a new context is not a "record broken".
        #expect(stats.recentRecords(days: 30, now: SFx.day(4)).isEmpty)

        // The user links both contexts → one class, one series.
        try store.workout.linkContexts(classes[0].representative, classes[1].representative, now: SFx.day(4))
        #expect(stats.contextClasses(exerciseId: bench.id).count == 1)
        #expect(stats.exerciseSeries(exerciseId: bench.id).map(\.workingLoad) == [60, 100])
    }

    @Test("M3: a running week is compared with the same elapsed days of the previous week")
    func toDateComparison() throws {
        let (store, routine, _) = try plannedStore()
        for d in [0, 2, 4, 7] {
            try SFx.performSession(store, routineId: routine.id, day: d, weight: 60, reps: [10, 10, 10])
        }
        let stats = StatsService(repository: store.repo, timeZone: SFx.tz)
        let c = stats.comparison(.week, now: SFx.day(8)) // Tuesday of week 2
        #expect(c.isToDate)
        #expect(c.current.validSessions == 1)   // Mon (day 7)
        #expect(c.previous.validSessions == 1)  // Mon–Tue of week 1 (day 0 only)
        let rolling = stats.comparison(.last30Days, now: SFx.day(8))
        #expect(!rolling.isToDate)
    }

    @Test("M4/minor 10: one recent record per kind and session, unique ids, never the first value of a kind")
    func recentRecordsDedup() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        // First session: 12-rep sets (above the 1RM cap) → no 1RM estimate yet.
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [12, 12, 12])
        // Second session: three heavier sets in one session.
        let s = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let log = store.repo.exerciseLogs(sessionId: s.id)[0]
        for (set, w) in zip(store.repo.setLogs(exerciseLogId: log.id), [62.5, 65, 67.5]) {
            var x = set; x.weight = w; x.reps = 10
            try store.workout.updateSet(x)
            try store.workout.completeSet(setId: x.id, now: SFx.day(3, minutes: 5))
        }
        try store.workout.finish(sessionId: s.id, now: SFx.day(3, minutes: 40))

        let recent = StatsService(repository: store.repo, timeZone: SFx.tz).recentRecords(days: 30, now: SFx.day(4))
        #expect(Set(recent.map(\.id)).count == recent.count)
        let maxWeight = recent.filter { $0.record.kind == .maxWeight }
        #expect(maxWeight.count == 1)
        #expect(maxWeight.first?.record.value == 67.5)
        // The first-ever 1RM estimate (session 2) is not a broken record.
        #expect(!recent.contains { $0.record.kind == .bestEstimatedOneRepMax })
    }

    @Test("Minor 8: a warm-up inside a superset does not jump to the other exercise")
    func warmupInSuperset() throws {
        let store = try TestStore()
        let routine = try store.routines.createRoutine(name: "Brazos", now: SFx.day(0))
        let curl = try store.catalog.createCustomExercise(name: "Curl", measurement: .weightReps, equipment: .dumbbell, loadMode: .perSide, primaryMuscles: [.biceps])
        let push = try store.catalog.createCustomExercise(name: "Tríceps", measurement: .weightReps, equipment: .cable, loadMode: .total, primaryMuscles: [.triceps])
        let a = try store.routines.addExercise(routineId: routine.id, exerciseId: curl.id, restSeconds: 60)
        let b = try store.routines.addExercise(routineId: routine.id, exerciseId: push.id)
        try store.routines.setSuperset(ids: [a.id, b.id], group: 1)
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let curlLog = store.repo.exerciseLogs(sessionId: session.id)[0]
        var warm = try store.workout.addSet(logId: curlLog.id, kind: .warmup)
        warm.weight = 8; warm.reps = 12
        try store.workout.updateSet(warm)
        try store.workout.completeSet(setId: warm.id, now: SFx.day(0, minutes: 1))
        #expect(store.workout.restAdvice(afterCompleting: warm.id) == RestAdvice(restSeconds: 60, nextExerciseLogId: nil))
    }

    @Test("Minor 9: the import summary counts what is really inserted")
    func importSummaryIsAccurate() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let backup = try store.export.exportJSON(now: SFx.day(0, minutes: 1))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        try store.workout.removeSet(setId: store.repo.setLogs(exerciseLogId: logId)[2].id)
        try store.workout.finish(sessionId: session.id, now: SFx.day(0, minutes: 30))
        let summary = try store.export.importJSON(backup)
        #expect(summary.inserted == 0)
        #expect(summary.conflicts >= 2) // the session (now finished) and the removed set
    }

    @Test("Minor 12: goals are dated when the record reached them")
    func goalAchievedDate() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10])
        try SFx.performSession(store, routineId: routine.id, day: 3, weight: 65, reps: [8, 8, 8])
        try store.repo.upsertGoal(Goal(exerciseId: bench.id, metric: .weight, value: 65, createdAt: SFx.day(1)))
        let stats = StatsService(repository: store.repo, timeZone: SFx.tz)
        let achieved = try stats.refreshGoals(now: SFx.day(20))
        #expect(achieved.first?.achievedAt == SFx.day(3))
    }

    @Test("Minor 17: CSV has measurement/load mode columns and neutralizes formulas")
    func csvColumnsAndInjection() throws {
        let store = try TestStore()
        let ex = try store.catalog.createCustomExercise(name: "=HYPERLINK(\"x\")", measurement: .weightReps, equipment: .dumbbell, loadMode: .perSide, primaryMuscles: [.biceps])
        let routine = try store.routines.createRoutine(name: "R", now: SFx.day(0))
        try store.routines.addExercise(routineId: routine.id, exerciseId: ex.id, override: ProgressionConfig(targetSets: 1))
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 12.5, reps: [10])
        let lines = store.export.exportSetsCSV().split(separator: "\n")
        #expect(lines[0].contains("measurement,load_mode"))
        #expect(lines[1].contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(lines[1].contains(",weightReps,perSide,"))
    }

    @Test("Finding 7: per-muscle weekly set goals are stored only when the user sets them")
    func muscleSetGoals() throws {
        var settings = UserSettings.default
        #expect(settings.weeklySetGoal(for: .chest) == nil)
        settings.setWeeklySetGoal(10, for: .chest)
        #expect(settings.weeklySetGoal(for: .chest) == 10)
        settings.setWeeklySetGoal(nil, for: .chest)
        #expect(settings.muscleSetGoals == nil)
    }
}
