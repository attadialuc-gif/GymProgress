import Foundation
@testable import GymCore
@testable import GymStore

/// A file-backed store that can be "reopened" (new instance from the same file = app relaunch).
@MainActor
final class TestStore {
    let url: URL
    private(set) var repo: JSONGymRepository

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gymprogress-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).json")
        repo = try JSONGymRepository(fileURL: url)
    }

    /// Drops the in-memory instance and reloads everything from disk.
    func reload() throws {
        repo = try JSONGymRepository(fileURL: url)
    }

    var workout: WorkoutService { WorkoutService(repository: repo, timeZone: SFx.tz) }
    var routines: RoutineService { RoutineService(repository: repo) }
    var catalog: ExerciseCatalogService { ExerciseCatalogService(repository: repo) }
    var history: HistoryService { HistoryService(repository: repo) }
    var export: ExportService { ExportService(repository: repo) }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

enum SFx {
    static let tz = TimeZone(identifier: "America/Argentina/Buenos_Aires")!

    /// 2026-01-05 18:00 local + n days.
    static func day(_ n: Int, minutes: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 18))!
        return base.addingTimeInterval(Double(n) * 86_400 + Double(minutes) * 60)
    }

    /// Bench press with the section 2.D reference config (3 × 8–12, RIR 2, +2.5 kg).
    @MainActor
    static func bench(in store: TestStore) throws -> Exercise {
        try store.catalog.createCustomExercise(
            name: "Press de banca",
            measurement: .weightReps,
            equipment: .barbell,
            loadMode: .total,
            primaryMuscles: [.chest],
            secondaryMuscles: [MuscleInvolvement(muscle: .triceps)],
            increment: 2.5,
            progression: ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5)
        )
    }

    /// Runs a whole session of one exercise through the services: start → open → (decision) →
    /// fill and complete each set → finish.
    @MainActor
    @discardableResult
    static func performSession(
        _ store: TestStore,
        routineId: UUID,
        day: Int,
        weight: Double,
        reps: [Int],
        rir: [Double?]? = nil,
        choice: DecisionChoice = .ignore
    ) throws -> (session: WorkoutSession, log: ExerciseLog) {
        let w = store.workout
        let session = try w.startSession(routineId: routineId, now: SFx.day(day))
        let log = store.repo.exerciseLogs(sessionId: session.id)[0]
        _ = try w.openExercise(logId: log.id, now: SFx.day(day, minutes: 1))
        try w.decide(logId: log.id, choice: choice, now: SFx.day(day, minutes: 2))
        var sets = store.repo.setLogs(exerciseLogId: log.id).filter { $0.kind == .working }
        while sets.count < reps.count { sets.append(try w.addSet(logId: log.id)) }
        for (i, r) in reps.enumerated() {
            var s = sets[i]
            s.weight = weight
            s.reps = r
            s.rir = rir?[i] ?? nil
            try w.updateSet(s)
            try w.completeSet(setId: s.id, now: SFx.day(day, minutes: 5 + i * 3))
        }
        let finished = try w.finish(sessionId: session.id, now: SFx.day(day, minutes: 60))
        return (finished, store.repo.exerciseLog(id: log.id)!)
    }

    @MainActor
    static func routine(with exercise: Exercise, in store: TestStore) throws -> RoutineTemplate {
        let routine = try store.routines.createRoutine(name: "Torso A", now: SFx.day(-1))
        try store.routines.addExercise(routineId: routine.id, exerciseId: exercise.id)
        return routine
    }
}
