import Foundation
import Testing
@testable import GymCore
@testable import GymStore

@MainActor
@Suite("Stage 4 — supersets, rest and session history")
struct Stage4Tests {

    @Test("Superset: alternate exercises without rest, rest after the round, plain rest otherwise")
    func supersetRestAdvice() throws {
        let store = try TestStore()
        let routine = try store.routines.createRoutine(name: "Brazos", now: SFx.day(0))
        let curl = try store.catalog.createCustomExercise(name: "Curl", measurement: .weightReps, equipment: .dumbbell, loadMode: .perSide, primaryMuscles: [.biceps], progression: ProgressionConfig(targetSets: 2))
        let push = try store.catalog.createCustomExercise(name: "Tríceps polea", measurement: .weightReps, equipment: .cable, loadMode: .total, primaryMuscles: [.triceps], progression: ProgressionConfig(targetSets: 2))
        let squat = try store.catalog.createCustomExercise(name: "Sentadilla", measurement: .weightReps, equipment: .barbell, loadMode: .total, primaryMuscles: [.quads], progression: ProgressionConfig(targetSets: 1))
        let a = try store.routines.addExercise(routineId: routine.id, exerciseId: curl.id, restSeconds: 90)
        let b = try store.routines.addExercise(routineId: routine.id, exerciseId: push.id, restSeconds: 90)
        try store.routines.addExercise(routineId: routine.id, exerciseId: squat.id, restSeconds: 180)
        try store.routines.setSuperset(ids: [a.id, b.id], group: 1)

        let session = try store.workout.startSession(routineId: routine.id, now: SFx.day(0))
        let logs = store.repo.exerciseLogs(sessionId: session.id)
        #expect(logs.map(\.supersetGroup) == [1, 1, nil])

        func complete(_ log: ExerciseLog, _ i: Int) throws -> RestAdvice {
            var s = store.repo.setLogs(exerciseLogId: log.id)[i]
            s.weight = 20
            s.reps = 10
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: SFx.day(0, minutes: 1))
            return store.workout.restAdvice(afterCompleting: s.id)
        }

        let afterA1 = try complete(logs[0], 0)
        #expect(afterA1 == RestAdvice(restSeconds: nil, nextExerciseLogId: logs[1].id))
        let afterB1 = try complete(logs[1], 0)
        #expect(afterB1 == RestAdvice(restSeconds: 90, nextExerciseLogId: logs[0].id))
        _ = try complete(logs[0], 1)
        let afterB2 = try complete(logs[1], 1)
        #expect(afterB2 == RestAdvice(restSeconds: 90, nextExerciseLogId: nil))
        let afterSquat = try complete(logs[2], 0)
        #expect(afterSquat == RestAdvice(restSeconds: 180, nextExerciseLogId: nil))
    }

    @Test("Session history lists completed sessions only, newest first, with volume and sets")
    func sessionSummaries() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10])
        try SFx.performSession(store, routineId: routine.id, day: 3, weight: 62.5, reps: [8, 8])
        let open = try store.workout.startSession(routineId: routine.id, now: SFx.day(5))
        try store.workout.discard(sessionId: open.id, now: SFx.day(5, minutes: 1))

        let summaries = store.history.completedSessionSummaries()
        #expect(summaries.count == 2)
        #expect(summaries[0].session.startedAt == SFx.day(3))
        #expect(summaries[0].effectiveSets == 2)
        #expect(summaries[0].volume == 62.5 * 16)
        #expect(summaries[1].volume == 600 * 3)
        #expect(summaries[0].exerciseNames == ["Press de banca"])
        #expect(summaries[0].duration == 60 * 60)
    }

    @Test("Stored logs without the newer optional fields still decode (schema v1 compatibility)")
    func oldLogDecodes() throws {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let (_, log) = try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10])
        var json = try JSONSerialization.jsonObject(with: GymJSON.encoder.encode(log)) as! [String: Any]
        json.removeValue(forKey: "supersetGroup")
        let decoded = try GymJSON.decoder.decode(ExerciseLog.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.supersetGroup == nil)
        #expect(decoded.id == log.id)
    }
}
