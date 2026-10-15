import Foundation
import SwiftData
import Testing
import GymCore
import GymStore
@testable import GymProgress

// UNVERIFIED (requires Xcode + iOS simulator). Runs the critical GymStore scenarios against the
// SwiftData repository, with a real on-disk store that is reopened between steps.

@MainActor
final class DiskStore {
    let url: URL
    private(set) var container: ModelContainer
    private(set) var repo: SwiftDataGymRepository

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("gp-\(UUID().uuidString).store")
        container = try SwiftDataGymRepository.makeContainer(url: url)
        repo = SwiftDataGymRepository(container: container)
    }

    func reload() throws {
        container = try SwiftDataGymRepository.makeContainer(url: url)
        repo = SwiftDataGymRepository(container: container)
    }

    var workout: WorkoutService { WorkoutService(repository: repo, timeZone: TimeZone(identifier: "America/Argentina/Buenos_Aires")!) }
}

private func day(_ n: Int, _ minutes: Int = 0) -> Date {
    Date(timeIntervalSince1970: 1_767_646_800).addingTimeInterval(Double(n) * 86_400 + Double(minutes) * 60)
}

@MainActor
@Suite("SwiftData repository")
struct SwiftDataRepositoryTests {

    func setUp(_ store: DiskStore) throws -> (Exercise, RoutineTemplate) {
        let bench = try ExerciseCatalogService(repository: store.repo).createCustomExercise(
            name: "Press de banca", measurement: .weightReps, equipment: .barbell, loadMode: .total,
            primaryMuscles: [.chest], increment: 2.5,
            progression: ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5)
        )
        let routines = RoutineService(repository: store.repo)
        let routine = try routines.createRoutine(name: "Torso A", now: day(-1))
        try routines.addExercise(routineId: routine.id, exerciseId: bench.id)
        return (bench, routine)
    }

    func perform(_ store: DiskStore, routine: RoutineTemplate, on d: Int, weight: Double, reps: [Int]) throws {
        let session = try store.workout.startSession(routineId: routine.id, now: day(d))
        let log = store.repo.exerciseLogs(sessionId: session.id)[0]
        _ = try store.workout.openExercise(logId: log.id, now: day(d, 1))
        for (set, r) in zip(store.repo.setLogs(exerciseLogId: log.id), reps) {
            var s = set
            s.weight = weight
            s.reps = r
            s.rir = 2
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: day(d, 5))
        }
        try store.workout.finish(sessionId: session.id, now: day(d, 60))
    }

    @Test("Case 8 on SwiftData: modified decision survives a container reload and is never overwritten")
    func case8() throws {
        let store = try DiskStore()
        let (bench, routine) = try setUp(store)
        try perform(store, routine: routine, on: 0, weight: 60, reps: [12, 12, 12])

        let session = try store.workout.startSession(routineId: routine.id, now: day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        let opened = try store.workout.openExercise(logId: logId, now: day(3, 1))
        #expect(opened.recommendation.targetWeight == 62.5)
        try store.workout.decide(logId: logId, choice: .modify(weight: 61, reps: [8, 8, 8]), now: day(3, 2))

        try store.reload()
        let decision = try #require(store.repo.decision(exerciseLogId: logId))
        #expect(decision.kind == .modified)
        #expect(decision.finalWeight == 61)
        #expect(decision.recommended.targetWeight == 62.5)
        let again = try store.workout.openExercise(logId: logId, now: day(3, 30))
        #expect(again.recommendation == opened.recommendation)
        #expect(again.decision == decision)
        _ = bench
    }

    @Test("Interrupted session is recovered after reopening the store")
    func recovery() throws {
        let store = try DiskStore()
        let (_, routine) = try setUp(store)
        let session = try store.workout.startSession(routineId: routine.id, now: day(0))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        try store.workout.decide(logId: logId, choice: .modify(weight: 40, reps: [10, 10, 10]), now: day(0, 1))
        try store.workout.completeSet(setId: store.repo.setLogs(exerciseLogId: logId)[0].id, now: day(0, 2))

        try store.reload()
        #expect(store.workout.openSession()?.id == session.id)
        #expect(store.repo.setLogs(exerciseLogId: logId)[0].status == .completed)
        #expect(store.repo.decision(exerciseLogId: logId)?.kind == .modified)
    }

    @Test("Export from SwiftData → import into another store: identical, no duplicates on re-import")
    func exportImport() throws {
        let source = try DiskStore()
        let (_, routine) = try setUp(source)
        try perform(source, routine: routine, on: 0, weight: 60, reps: [12, 12, 12])
        let data = try ExportService(repository: source.repo).exportJSON(now: day(1))

        let target = try DiskStore()
        try ExportService(repository: target.repo).importJSON(data)
        try ExportService(repository: target.repo).importJSON(data)
        try target.reload()
        #expect(target.repo.snapshot() == source.repo.snapshot())
    }

    @Test("Accepted and ignored decisions persist on SwiftData and survive recomputation", arguments: [DecisionChoice.accept, DecisionChoice.ignore])
    func decisionKinds(choice: DecisionChoice) throws {
        let store = try DiskStore()
        let (bench, routine) = try setUp(store)
        try perform(store, routine: routine, on: 0, weight: 60, reps: [12, 12, 12])
        let session = try store.workout.startSession(routineId: routine.id, now: day(3))
        let logId = store.repo.exerciseLogs(sessionId: session.id)[0].id
        let first = try store.workout.openExercise(logId: logId, now: day(3, 1))
        let decision = try store.workout.decide(logId: logId, choice: choice, now: day(3, 2))
        try store.reload()
        _ = store.workout.previewRecommendation(exerciseId: bench.id, now: day(3, 3))
        let again = try store.workout.openExercise(logId: logId, now: day(3, 4))
        #expect(again.decision == decision)
        #expect(again.recommendation == first.recommendation)
        let weights = store.repo.setLogs(exerciseLogId: logId).map(\.weight)
        #expect(weights == (choice == .accept ? [62.5, 62.5, 62.5] : [nil, nil, nil]))
    }

    @Test("Section 2.E flow on SwiftData, reopening the container between steps")
    func endToEndFlow() throws {
        let store = try DiskStore()
        try ExerciseCatalogService(repository: store.repo).seed(try ExerciseCatalog.bundled())
        try store.reload()
        let routines = RoutineService(repository: store.repo)
        let routine = try routines.createRoutine(name: "Torso A", now: day(0))
        let bench = try #require(store.repo.exercises().first { $0.catalogId == "barbell-bench-press" })
        try routines.addExercise(routineId: routine.id, exerciseId: bench.id,
                                 override: ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, initialWeight: 50, increment: 2.5))
        try store.reload()

        let s1 = try store.workout.startSession(routineId: routine.id, now: day(1))
        let log1 = store.repo.exerciseLogs(sessionId: s1.id)[0]
        #expect(try store.workout.openExercise(logId: log1.id, now: day(1, 1)).recommendation.targetWeight == 50)
        try store.workout.decide(logId: log1.id, choice: .accept, now: day(1, 2))
        try store.reload()
        for set in store.repo.setLogs(exerciseLogId: log1.id) {
            var s = set
            s.reps = 12
            s.rir = 2
            try store.workout.updateSet(s)
            try store.workout.completeSet(setId: s.id, now: day(1, 10))
            try store.reload()
        }
        try store.workout.finish(sessionId: s1.id, now: day(1, 45))
        try store.reload()

        #expect(HistoryService(repository: store.repo).exerciseHistory(exerciseId: bench.id).count == 1)
        let next = try #require(store.workout.previewRecommendation(exerciseId: bench.id, now: day(3)))
        #expect(next.action == .increaseWeight)
        #expect(next.targetWeight == 52.5)
    }

    @Test("Migration plan opens a v1 store")
    func migrationPlan() throws {
        let store = try DiskStore()
        _ = try setUp(store)
        try store.reload() // opens with GymMigrationPlan
        #expect(store.repo.routines().count == 1)
    }
}
