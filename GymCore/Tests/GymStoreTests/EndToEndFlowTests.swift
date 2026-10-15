import Foundation
import Testing
@testable import GymCore
@testable import GymStore

@MainActor
@Suite("Section 2.E — end-to-end flow")
struct EndToEndFlowTests {

    /// Crear rutina → seleccionar ejercicio → definir objetivo → registrar series → guardar la sesión
    /// → consultar el historial → recibir la recomendación para la próxima sesión.
    /// The store is reloaded from disk between every step (= closing and reopening the app).
    @Test("Full flow with persistent data and a reload between every step")
    func fullFlow() throws {
        let store = try TestStore()
        try store.catalog.seed(try ExerciseCatalog.bundled())
        try store.reload()

        // 1. Create a routine.
        let routine = try store.routines.createRoutine(name: "Torso A", now: SFx.day(0))
        try store.reload()

        // 2. Select an exercise from the library.
        let bench = try #require(store.repo.exercises().first { $0.catalogId == "barbell-bench-press" })
        // 3. Define the target: 3 × 8–12 @ RIR 2, initial load 50 kg, +2.5 kg.
        let target = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, initialWeight: 50, increment: 2.5)
        try store.routines.addExercise(routineId: routine.id, exerciseId: bench.id, override: target)
        try store.reload()
        #expect(store.repo.routineExercises(routineId: routine.id).count == 1)

        // Routine preview already shows the initial target (no invented number).
        let preview = try #require(store.workout.previewRecommendations(routineId: routine.id, now: SFx.day(0)).first?.2)
        #expect(preview.action == .needsInitialTarget)
        #expect(preview.targetWeight == 50)

        // 4. Record sets: start, open the exercise (recommendation card), accept, complete.
        let s1 = try store.workout.startSession(routineId: routine.id, now: SFx.day(1))
        let log1 = store.repo.exerciseLogs(sessionId: s1.id)[0]
        let card = try store.workout.openExercise(logId: log1.id, now: SFx.day(1, minutes: 1))
        #expect(card.recommendation.reason == .initialTarget)
        #expect(card.recommendation.target.repMin == 8 && card.recommendation.target.repMax == 12)
        try store.workout.decide(logId: log1.id, choice: .accept, now: SFx.day(1, minutes: 2))
        try store.reload()

        for (i, reps) in [12, 12, 12].enumerated() {
            var set = store.repo.setLogs(exerciseLogId: log1.id)[i]
            #expect(set.weight == 50) // pre-filled by "Aceptar"
            set.reps = reps
            set.rir = 2
            try store.workout.updateSet(set)
            try store.workout.completeSet(setId: set.id, now: SFx.day(1, minutes: 5 + 3 * i))
            try store.reload() // every completed set is already on disk
        }

        // 5. Save (finish) the session.
        try store.workout.finish(sessionId: s1.id, now: SFx.day(1, minutes: 45))
        try store.reload()
        #expect(store.workout.openSession() == nil)

        // 6. History.
        let history = store.history.exerciseHistory(exerciseId: bench.id)
        #expect(history.count == 1)
        #expect(history[0].sets.map(\.reps) == [12, 12, 12])
        #expect(history[0].decision?.kind == .accepted)

        // 7. Recommendation for the next session, from the recorded data.
        let next = try #require(store.workout.previewRecommendation(exerciseId: bench.id, config: target, now: SFx.day(3)))
        #expect(next.action == .increaseWeight)
        #expect(next.targetWeight == 52.5)
        #expect(next.targetReps == [8, 8, 8])
        #expect(next.confidence == .high)
        #expect(next.lastPerformance?.amounts == [12, 12, 12])

        // And the next session's card shows exactly that, frozen.
        let s2 = try store.workout.startSession(routineId: routine.id, now: SFx.day(3))
        let log2 = store.repo.exerciseLogs(sessionId: s2.id)[0]
        let card2 = try store.workout.openExercise(logId: log2.id, now: SFx.day(3, minutes: 1))
        #expect(card2.recommendation.targetWeight == 52.5)
        #expect(card2.recommendation.reasonText.contains("52,5 kg"))
    }

    @Test("Performance: ~2 years of history keeps the engine and history queries fast")
    func twoYearsOfData() throws {
        let repo = try JSONGymRepository()
        let catalog = ExerciseCatalogService(repository: repo)
        let bench = try catalog.createCustomExercise(name: "Press", measurement: .weightReps, equipment: .barbell, loadMode: .total, primaryMuscles: [.chest])
        let others = try (0..<5).map { i in
            try catalog.createCustomExercise(name: "Ej \(i)", measurement: .weightReps, equipment: .machine, loadMode: .total, primaryMuscles: [.quads])
        }

        // Synthetic data (tests only): 4 sessions/week × 104 weeks × 6 exercises × 4 sets.
        try repo.batch {
            var weight = 40.0
            for n in 0..<416 {
                let start = SFx.day(n * 7 / 4)
                let session = WorkoutSession(routineId: nil, routineNameSnapshot: "Gen", startedAt: start, endedAt: start.addingTimeInterval(3600), status: .completed, updatedAt: start)
                try repo.upsertSession(session)
                for (order, ex) in ([bench] + others).enumerated() {
                    let log = ExerciseLog(sessionId: session.id, exerciseId: ex.id, snapshot: ExerciseSnapshot(ex), configSnapshot: ex.progression, plannedOrder: order)
                    try repo.upsertExerciseLog(log)
                    for i in 0..<4 {
                        try repo.upsertSetLog(SetLog(exerciseLogId: log.id, index: i, status: .completed, weight: weight, reps: 8 + (n % 5), rir: 2, completedAt: start))
                    }
                }
                if n % 10 == 9 { weight += 2.5 }
            }
        }
        #expect(repo.sessions().count == 416)

        let service = WorkoutService(repository: repo, timeZone: SFx.tz)
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            for _ in 0..<5 {
                _ = try #require(service.previewRecommendation(exerciseId: bench.id, now: SFx.day(800)))
            }
            _ = HistoryService(repository: repo).exerciseHistory(exerciseId: bench.id)
            _ = HistoryService(repository: repo).sessionDigests()
        }
        // Debug build bound; measured ≈ 0.15 s on the development machine (WSL).
        #expect(elapsed < .seconds(2))
        print("2-year dataset: 5 recommendations + history + digests in \(elapsed)")
    }
}
