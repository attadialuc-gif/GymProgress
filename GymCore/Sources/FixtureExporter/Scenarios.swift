import Foundation
import GymCore
import GymStore

/// GymStore test cases (PersistenceTests, EndToEndFlowTests, ReviewRegressionTests, Stage4Tests,
/// Stage5And6Tests, Stage4To7ReviewTests) expressed as operation scripts.
enum Scenarios {
    typealias Op = [String: Any]

    /// 2026-01-05 18:00 Buenos Aires + days + minutes (same as SFx.day in the store tests).
    static func t(_ d: Int, _ m: Int = 0) -> Double {
        FX.date(2026, 1, 5, 18, 0, tz: FX.ba).timeIntervalSince1970 + Double(d) * 86_400 + Double(m) * 60
    }

    static func cfg(_ c: ProgressionConfig) -> Any { json(c) }
    static let benchConfig = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5)

    static func bench(_ alias: String = "bench") -> Op {
        ["op": "createExercise", "alias": alias, "name": "Press de banca", "measurement": "weightReps", "equipment": "barbell",
         "loadMode": "total", "primary": ["chest"], "secondary": [["muscle": "triceps"]], "increment": 2.5, "progression": cfg(benchConfig)]
    }

    static func exercise(_ alias: String, _ name: String, _ measurement: String = "weightReps", _ equipment: String = "machine",
                         _ loadMode: String = "total", primary: [String], progression: ProgressionConfig? = nil) -> Op {
        var op: Op = ["op": "createExercise", "alias": alias, "name": name, "measurement": measurement, "equipment": equipment,
                      "loadMode": loadMode, "primary": primary, "secondary": [Any](), "increment": 2.5]
        if let progression { op["progression"] = cfg(progression) }
        return op
    }

    static func routine(_ alias: String = "r", name: String = "Torso A", exercise: String = "bench") -> [Op] {
        [["op": "createRoutine", "alias": alias, "name": name, "at": t(-1)],
         ["op": "addRoutineExercise", "alias": "\(alias).\(exercise)", "routine": alias, "exercise": exercise]]
    }

    static func choice(_ kind: String, weight: Double? = nil, reps: [Int] = []) -> [String: Any] {
        var c: [String: Any] = ["kind": kind, "reps": reps]
        if let weight { c["weight"] = weight }
        return c
    }

    /// Same as SFx.performSession: start → open → decide → fill & complete each set → finish.
    static func perform(_ s: String, routine: String = "r", day: Int, weight: Double, reps: [Int], rir: [Double?]? = nil,
                        choice c: [String: Any] = choice("ignore"), targetSets: Int = 3, store: String? = nil) -> [Op] {
        var ops: [Op] = [
            ["op": "startSession", "alias": s, "routine": routine, "at": t(day)],
            ["op": "openExercise", "log": "\(s).0", "at": t(day, 1)],
            ["op": "decide", "log": "\(s).0", "choice": c, "at": t(day, 2)],
        ]
        for _ in max(targetSets, 0)..<max(reps.count, targetSets) { ops.append(["op": "addSet", "log": "\(s).0", "kind": "working"]) }
        for (i, r) in reps.enumerated() {
            var u: Op = ["op": "updateSet", "log": "\(s).0", "pos": i, "weight": weight, "reps": r]
            u["rir"] = rir.flatMap { $0[i] } ?? NSNull()
            ops.append(u)
            ops.append(["op": "completeSet", "log": "\(s).0", "pos": i, "at": t(day, 5 + i * 3)])
        }
        ops.append(["op": "finish", "session": s, "at": t(day, 60)])
        if let store { ops = ops.map { var o = $0; o["store"] = store; return o } }
        return ops
    }

    static func all() -> [(String, [Op])] {
        var list: [(String, [Op])] = []
        let base = [bench()] + routine()

        // MARK: PersistenceTests
        list.append(("case 2.D-8 modified decision lifecycle", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "openExercise", "log": "s2.0", "at": t(3, 1)],
            ["op": "decide", "log": "s2.0", "choice": choice("modify", weight: 61, reps: [8, 8, 8]), "at": t(3, 2)],
            ["op": "reload"],
            ["op": "observeDecision", "log": "s2.0"],
            ["op": "openSession"],
            ["op": "openExercise", "log": "s2.0", "at": t(3, 40)],
            ["op": "preview", "exercise": "bench", "at": t(3, 41)],
            ["op": "setContext", "log": "s2.0", "at": t(3, 42)],
            ["op": "observeDecision", "log": "s2.0"],
            ["op": "observeLog", "log": "s2.0"],
            ["op": "updateSet", "log": "s2.0", "pos": 0, "reps": 10, "rir": 2], ["op": "completeSet", "log": "s2.0", "pos": 0, "at": t(3, 50)],
            ["op": "updateSet", "log": "s2.0", "pos": 1, "reps": 9, "rir": 2], ["op": "completeSet", "log": "s2.0", "pos": 1, "at": t(3, 50)],
            ["op": "updateSet", "log": "s2.0", "pos": 2, "reps": 9, "rir": 2], ["op": "completeSet", "log": "s2.0", "pos": 2, "at": t(3, 50)],
            ["op": "finish", "session": "s2", "at": t(3, 70)],
            ["op": "reload"],
            ["op": "preview", "exercise": "bench", "at": t(6)],
            ["op": "observeDecision", "log": "s2.0"],
        ]))
        for (name, c) in [("accept", choice("accept")), ("modify", choice("modify", weight: 61, reps: [10, 9, 8])), ("ignore", choice("ignore"))] {
            list.append(("decision kind \(name) persists", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]) + [
                ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
                ["op": "openExercise", "log": "s2.0", "at": t(3, 1)],
                ["op": "decide", "log": "s2.0", "choice": c, "at": t(3, 2)],
                ["op": "reload"],
                ["op": "openExercise", "log": "s2.0", "at": t(4)],
            ]))
        }
        list.append(("change decision keeps original snapshot", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "decide", "log": "s2.0", "choice": choice("accept"), "at": t(3, 1)],
            ["op": "decide", "log": "s2.0", "choice": choice("ignore"), "at": t(3, 2)],
            ["op": "observeSets", "log": "s2.0"],
        ]))
        list.append(("context change before decision + link", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "openExercise", "log": "s2.0", "at": t(3)],
            ["op": "setContext", "log": "s2.0", "equipment": "Smith", "at": t(3, 1)],
            ["op": "openExercise", "log": "s2.0", "at": t(3, 2)],
            ["op": "linkContexts", "a": ["log": "s2.0"], "b": ["exercise": "bench", "loadMode": "total"], "at": t(3, 3)],
            ["op": "preview", "exercise": "bench", "at": t(3, 4)],
        ]))
        list.append(("interrupted session recovery", base + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "openExercise", "log": "s1.0", "at": t(0, 1)],
            ["op": "decide", "log": "s1.0", "choice": choice("modify", weight: 40, reps: [10, 10, 10]), "at": t(0, 2)],
            ["op": "completeSet", "log": "s1.0", "pos": 0, "at": t(0, 5)],
            ["op": "pause", "session": "s1", "at": t(0, 10)],
            ["op": "reload"],
            ["op": "openSession"],
            ["op": "observeSession", "session": "s1", "at": t(0, 20)],
            ["op": "observeSets", "log": "s1.0"],
            ["op": "observeDecision", "log": "s1.0"],
            ["op": "resume", "session": "s1", "at": t(0, 25)],
            ["op": "observeSession", "session": "s1", "at": t(0, 30)],
        ]))
        list.append(("single open session", base + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(0, 1)],
        ]))
        list.append(("complete set rules", [bench(), exercise("row", "Remo", "weightReps", "cable", primary: ["upperBack"]),
                                            ["op": "createRoutine", "alias": "r", "name": "R", "at": t(0)],
                                            ["op": "addRoutineExercise", "alias": "r.bench", "routine": "r", "exercise": "bench"],
                                            ["op": "addRoutineExercise", "alias": "r.row", "routine": "r", "exercise": "row"]] + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "completeSet", "log": "s1.1", "pos": 0, "at": t(0)],
            ["op": "updateSet", "log": "s1.1", "pos": 0, "weight": -5, "reps": 10],
            ["op": "updateSet", "log": "s1.1", "pos": 0, "weight": 50, "reps": 12],
            ["op": "completeSet", "log": "s1.1", "pos": 0, "at": t(0, 5)],
            ["op": "updateSet", "log": "s1.0", "pos": 0, "weight": 60, "reps": 8],
            ["op": "completeSet", "log": "s1.0", "pos": 0, "at": t(0, 10)],
            ["op": "observeLog", "log": "s1.1"],
            ["op": "observeLog", "log": "s1.0"],
            ["op": "updateSet", "log": "s1.0", "pos": 1, "weightText": "62,5", "reps": 8],
            ["op": "updateSet", "log": "s1.0", "pos": 2, "rir": 11],
            ["op": "observeSets", "log": "s1.0"],
        ]))
        list.append(("copy previous loads", base + perform("s1", day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "decide", "log": "s2.0", "choice": choice("ignore"), "at": t(3)],
            ["op": "copyPreviousLoads", "log": "s2.0", "at": t(3, 1)],
        ]))
        list.append(("session-only changes", base + [
            exercise("curl", "Curl", "weightReps", "dumbbell", "perSide", primary: ["biceps"]),
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "addExerciseToSession", "session": "s1", "exercise": "curl", "alias": "s1.curl", "at": t(0)],
            ["op": "moveExercises", "session": "s1", "order": ["s1.curl", "s1.0"]],
            ["op": "removeExercise", "log": "s1.0"],
            ["op": "routineExercises", "routine": "r"],
        ]))
        list.append(("archive and delete never alter history", base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + [
            ["op": "deleteRoutine", "routine": "r"],
            ["op": "deleteExercise", "exercise": "bench"],
            ["op": "setRoutineArchived", "routine": "r", "archived": true],
            ["op": "setExerciseArchived", "exercise": "bench", "archived": true],
            ["op": "renameExercise", "exercise": "bench", "name": "Otro nombre"],
            ["op": "renameRoutine", "routine": "r", "name": "Rutina renombrada"],
            ["op": "reload"],
            ["op": "observeSession", "session": "s1", "at": t(1)],
            ["op": "observeLog", "log": "s1.0"],
            ["op": "observeSets", "log": "s1.0"],
            ["op": "exerciseHistory", "exercise": "bench"],
            exercise("unused", "Sin uso", primary: ["quads"]),
            ["op": "deleteExercise", "exercise": "unused"],
            ["op": "counts"],
        ]))
        list.append(("config edits never rewrite history", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]) + [
            ["op": "updateExerciseProgression", "exercise": "bench", "config": cfg(ProgressionConfig(targetSets: 5, repMin: 3, repMax: 5, targetRIR: 1, increment: 5))],
            ["op": "updateRoutineExerciseOverride", "item": "r.bench", "override": cfg(ProgressionConfig(targetSets: 4, repMin: 6, repMax: 8))],
            ["op": "reload"],
            ["op": "observeLog", "log": "s1.0"],
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "observeLog", "log": "s2.0"],
            ["op": "observeSets", "log": "s2.0"],
        ]))
        list.append(("export → import round trip, no duplicates", base
            + perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], choice: choice("accept"))
            + perform("s2", day: 3, weight: 62.5, reps: [8, 8, 8], choice: choice("modify", weight: 62.5, reps: [9, 9, 9])) + [
            ["op": "linkContexts", "a": ["exercise": "bench", "equipment": "A", "loadMode": "total"], "b": ["exercise": "bench", "loadMode": "total"], "at": t(4)],
            ["op": "export", "blob": "b1", "at": t(5)],
            ["op": "import", "blob": "b1", "store": "target"],
            ["op": "snapshotEquals", "a": "main", "b": "target"],
            ["op": "counts", "store": "target"],
            ["op": "import", "blob": "b1", "store": "target"],
            ["op": "reload", "store": "target"],
            ["op": "snapshotEquals", "a": "main", "b": "target"],
        ]))
        list.append(("import validation", [
            ["op": "importRaw", "json": ["schemaVersion": GymSchema.currentVersion + 1, "exercises": [Any](), "routines": [Any](), "routineExercises": [Any](),
                                         "schedule": [Any](), "sessions": [Any](), "exerciseLogs": [Any](), "setLogs": [Any](), "decisions": [Any](),
                                         "comparabilityLinks": [Any](), "goals": [Any](), "settings": json(UserSettings.default)]],
            ["op": "importRaw", "json": json(GymDatabase(setLogs: [SetLog(id: FX.uuid(0xE1), exerciseLogId: FX.uuid(0xE2), index: 0)]))],
            ["op": "importText", "text": "no es json"],
            ["op": "counts"],
        ]))
        list.append(("csv export", base + perform("s1", day: 0, weight: 62.5, reps: [8, 8, 8], rir: [2, 2, 2]) + [["op": "csv"]]))
        list.append(("catalog seeding and presets", [
            exercise("mine", "Mi ejercicio", "weightReps", "other", primary: ["abs"]),
            ["op": "seedCatalog"],
            ["op": "updateExerciseProgression", "exercise": "cat:barbell-bench-press", "config": cfg(ProgressionConfig(targetSets: 5, repMin: 3, repMax: 5, increment: 1.25))],
            ["op": "seedCatalog"],
            ["op": "exercise", "exercise": "cat:barbell-bench-press"],
            ["op": "exercise", "exercise": "mine"],
            ["op": "createRoutineFromPreset", "alias": "fb", "preset": "full-body-a", "at": t(0)],
            ["op": "counts"],
        ]))

        // MARK: EndToEndFlowTests
        let target = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, initialWeight: 50, increment: 2.5)
        list.append(("2.E full flow with reloads", [
            ["op": "seedCatalog"], ["op": "reload"],
            ["op": "createRoutine", "alias": "r", "name": "Torso A", "at": t(0)], ["op": "reload"],
            ["op": "addRoutineExercise", "alias": "r.bench", "routine": "r", "exercise": "cat:barbell-bench-press", "override": cfg(target)], ["op": "reload"],
            ["op": "previewRoutine", "routine": "r", "at": t(0)],
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(1)],
            ["op": "openExercise", "log": "s1.0", "at": t(1, 1)],
            ["op": "decide", "log": "s1.0", "choice": choice("accept"), "at": t(1, 2)], ["op": "reload"],
            ["op": "updateSet", "log": "s1.0", "pos": 0, "reps": 12, "rir": 2], ["op": "completeSet", "log": "s1.0", "pos": 0, "at": t(1, 5)], ["op": "reload"],
            ["op": "updateSet", "log": "s1.0", "pos": 1, "reps": 12, "rir": 2], ["op": "completeSet", "log": "s1.0", "pos": 1, "at": t(1, 8)], ["op": "reload"],
            ["op": "updateSet", "log": "s1.0", "pos": 2, "reps": 12, "rir": 2], ["op": "completeSet", "log": "s1.0", "pos": 2, "at": t(1, 11)], ["op": "reload"],
            ["op": "finish", "session": "s1", "at": t(1, 45)], ["op": "reload"],
            ["op": "openSession"],
            ["op": "exerciseHistory", "exercise": "cat:barbell-bench-press"],
            ["op": "preview", "exercise": "cat:barbell-bench-press", "config": cfg(target), "at": t(3)],
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "openExercise", "log": "s2.0", "at": t(3, 1)],
        ]))

        // MARK: Stage 4
        list.append(("superset rest advice", [
            ["op": "createRoutine", "alias": "r", "name": "Brazos", "at": t(0)],
            exercise("curl", "Curl", "weightReps", "dumbbell", "perSide", primary: ["biceps"], progression: ProgressionConfig(targetSets: 2)),
            exercise("push", "Tríceps polea", "weightReps", "cable", primary: ["triceps"], progression: ProgressionConfig(targetSets: 2)),
            exercise("squat", "Sentadilla", "weightReps", "barbell", primary: ["quads"], progression: ProgressionConfig(targetSets: 1)),
            ["op": "addRoutineExercise", "alias": "r.curl", "routine": "r", "exercise": "curl", "restSeconds": 90],
            ["op": "addRoutineExercise", "alias": "r.push", "routine": "r", "exercise": "push", "restSeconds": 90],
            ["op": "addRoutineExercise", "alias": "r.squat", "routine": "r", "exercise": "squat", "restSeconds": 180],
            ["op": "setSuperset", "items": ["r.curl", "r.push"], "group": 1],
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "addSet", "log": "s1.0", "kind": "warmup"],
        ] + [("s1.0", 0), ("s1.1", 0), ("s1.0", 1), ("s1.1", 1), ("s1.2", 0)].flatMap { log, pos -> [Op] in [
            ["op": "updateSet", "log": log, "pos": pos, "weight": 20, "reps": 10],
            ["op": "completeSet", "log": log, "pos": pos, "at": t(0, 1)],
            ["op": "restAdvice", "log": log, "pos": pos],
        ] } + [
            ["op": "updateSet", "log": "s1.0", "pos": 2, "weight": 8, "reps": 12],
            ["op": "completeSet", "log": "s1.0", "pos": 2, "at": t(0, 2)],
            ["op": "restAdvice", "log": "s1.0", "pos": 2],
            ["op": "observeLog", "log": "s1.0"],
        ]))
        list.append(("session summaries", base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10])
            + perform("s2", day: 3, weight: 62.5, reps: [8, 8]) + [
            ["op": "startSession", "alias": "s3", "routine": "r", "at": t(5)],
            ["op": "discard", "session": "s3", "at": t(5, 1)],
            ["op": "sessionSummaries"],
            ["op": "sessionDigests"],
        ]))

        // MARK: Review regressions (stages 2–3)
        list.append(("older backup never overwrites", base + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "export", "blob": "old", "at": t(0, 1)],
            ["op": "decide", "log": "s1.0", "choice": choice("modify", weight: 50, reps: [10, 10, 10]), "at": t(0, 2)],
            ["op": "completeSet", "log": "s1.0", "pos": 0, "at": t(0, 5)],
            ["op": "completeSet", "log": "s1.0", "pos": 1, "at": t(0, 5)],
            ["op": "completeSet", "log": "s1.0", "pos": 2, "at": t(0, 5)],
            ["op": "finish", "session": "s1", "at": t(0, 50)],
            ["op": "export", "blob": "before", "at": t(0, 51)],
            ["op": "import", "blob": "old"],
            ["op": "observeSession", "session": "s1", "at": t(1)],
            ["op": "exerciseHistory", "exercise": "bench"],
            ["op": "counts"],
        ]))
        list.append(("second open session refused on import", ([bench("benchB")] + routine("rB", exercise: "benchB")).map { var o = $0; o["store"] = "other"; return o } + [
            ["op": "startSession", "alias": "sB", "routine": "rB", "at": t(0), "store": "other"],
            ["op": "export", "blob": "otherOpen", "at": t(0, 1), "store": "other"],
        ] + base + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(1)],
            ["op": "import", "blob": "otherOpen"],
            ["op": "counts"],
        ]))
        list.append(("settings only into empty store", [
            ["op": "saveSettings", "patch": ["weeklyGoal": 5], "store": "src"],
            bench().merging(["store": "src"]) { $1 },
        ] + routine().map { $0.merging(["store": "src"]) { $1 } } + [
            ["op": "export", "blob": "s", "at": t(0), "store": "src"],
            ["op": "import", "blob": "s", "store": "empty"],
            ["op": "settings", "store": "empty"],
            bench("usedBench").merging(["store": "used"]) { $1 },
        ] + routine("usedR", exercise: "usedBench").map { $0.merging(["store": "used"]) { $1 } } + [
            ["op": "import", "blob": "s", "store": "used"],
            ["op": "settings", "store": "used"],
        ]))
        list.append(("switch context treating as equivalent", base + [
            ["op": "startSession", "alias": "s0", "routine": "r", "at": t(0)],
            ["op": "setContext", "log": "s0.0", "equipment": "Máquina A", "at": t(0)],
        ] + (0..<3).flatMap { i -> [Op] in [
            ["op": "updateSet", "log": "s0.0", "pos": i, "weight": 60, "reps": 12, "rir": 2],
            ["op": "completeSet", "log": "s0.0", "pos": i, "at": t(0, 5)],
        ] } + [
            ["op": "finish", "session": "s0", "at": t(0, 40)],
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(3)],
            ["op": "observeLog", "log": "s1.0"],
            ["op": "openExercise", "log": "s1.0", "at": t(3)],
            ["op": "switchContextEquivalent", "log": "s1.0", "equipment": "Máquina B", "at": t(3, 1)],
            ["op": "openExercise", "log": "s1.0", "at": t(3, 2)],
        ]))
        list.append(("finished session is structurally immutable", base + perform("s1", day: 0, weight: 60, reps: [11, 10]) + [
            ["op": "removeSet", "log": "s1.0", "pos": 0],
            ["op": "completeSet", "log": "s1.0", "pos": 2, "at": t(1)],
            ["op": "decide", "log": "s1.0", "choice": choice("accept"), "at": t(1)],
            ["op": "addSet", "log": "s1.0", "kind": "working"],
            ["op": "observeSets", "log": "s1.0"],
        ]))
        list.append(("copy from non-equivalent needs explicit choice", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "setContext", "log": "s2.0", "equipment": "Smith", "at": t(3)],
            ["op": "copyPreviousLoads", "log": "s2.0", "at": t(3)],
            ["op": "observeSets", "log": "s2.0"],
            ["op": "copyPreviousLoads", "log": "s2.0", "allowNonEquivalent": true, "at": t(3)],
        ]))
        list.append(("initial target stored in routine override", [bench(),
            ["op": "createRoutine", "alias": "r", "name": "R", "at": t(0)],
            ["op": "addRoutineExercise", "alias": "r.bench", "routine": "r", "exercise": "bench",
             "override": cfg(ProgressionConfig(targetSets: 4, repMin: 5, repMax: 8, targetRIR: 1, increment: 5))],
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "openExercise", "log": "s1.0", "at": t(0)],
            ["op": "setInitialTarget", "log": "s1.0", "weight": 70, "reps": [5, 5, 5, 5], "at": t(0, 1)],
            ["op": "routineExercises", "routine": "r"],
            ["op": "exercise", "exercise": "bench"],
        ] + (0..<4).flatMap { i -> [Op] in [
            ["op": "updateSet", "log": "s1.0", "pos": i, "reps": 8, "rir": 1],
            ["op": "completeSet", "log": "s1.0", "pos": i, "at": t(0, 10)],
        ] } + [
            ["op": "finish", "session": "s1", "at": t(0, 50)],
            ["op": "preview", "exercise": "bench", "at": t(2)],
        ]))
        list.append(("merge keeps schedule append-only", [
            ["op": "mergeRaw", "includeSettings": false,
             "json": json(GymDatabase(schedule: [ScheduleEntry(id: FX.uuid(0xABCD), weekday: 2, routineId: nil, validFrom: Date(timeIntervalSince1970: t(0)), createdAt: Date(timeIntervalSince1970: t(0)))]))],
            ["op": "mergeRaw", "includeSettings": false,
             "json": json(GymDatabase(schedule: [ScheduleEntry(id: FX.uuid(0xABCD), weekday: 5, routineId: nil, validFrom: Date(timeIntervalSince1970: t(0)), createdAt: Date(timeIntervalSince1970: t(0)))]))],
            ["op": "scheduleEntries"],
        ]))

        // MARK: Stage 5 & 6
        let plan: Op = ["op": "setWeeklyPlan", "assignments": ["2": "r", "4": "r", "6": "r"], "from": t(0), "at": t(0)]
        list.append(("calendar days and plan change", base + [plan] + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + [
            ["op": "calendarWeek", "date": t(0), "at": t(3)],
        ] + perform("s2", day: 4, weight: 60, reps: [10, 10, 10]) + [
            ["op": "setWeeklyPlan", "assignments": ["3": "r"], "from": t(7), "at": t(5)],
            ["op": "calendarWeek", "date": t(0), "at": t(8)],
            ["op": "calendarWeek", "date": t(7), "at": t(5)],
            ["op": "calendarMonth", "date": t(0), "at": t(3)],
            ["op": "plan", "asOf": t(8)],
        ]))
        list.append(("streaks and weekly goal", base + [plan]
            + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + perform("s2", day: 2, weight: 60, reps: [10, 10, 10])
            + perform("s3", day: 4, weight: 60, reps: [10, 10, 10]) + [
            ["op": "weekSummary", "at": t(5)],
            ["op": "streak", "at": t(8)],
            ["op": "saveSettings", "patch": ["streakMode": "dayGap", "maxGapDays": 2]],
            ["op": "streak", "at": t(5)],
            ["op": "streak", "at": t(8)],
        ]))
        list.append(("invalid sessions don't count", base + [plan] + perform("s1", day: 0, weight: 60, reps: [10]) + [
            ["op": "calendarWeek", "date": t(0), "at": t(1)],
            ["op": "weekSummary", "at": t(1)],
        ]))
        let statsBase = base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2])
            + perform("s2", day: 2, weight: 60, reps: [11, 10, 10], rir: [2, 2, 2]) + perform("s3", day: 8, weight: 62.5, reps: [10, 9, 8], rir: [2, 2, 2])
        list.append(("stats periods, totals, series, muscles, records, goals", statsBase + [
            ["op": "periodIntervals", "period": ["kind": "week"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "last30Days"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "calendarMonth"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "calendarYear"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "last90Days"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "last12Months"], "at": t(3)],
            ["op": "periodIntervals", "period": ["kind": "custom", "start": t(-10), "end": t(2)], "at": t(3)],
            ["op": "comparison", "period": ["kind": "week"], "at": t(9)],
            ["op": "comparison", "period": ["kind": "last30Days"], "at": t(9)],
            ["op": "comparison", "period": ["kind": "week"], "at": t(9), "routine": "r"],
            ["op": "exerciseSeries", "exercise": "bench"],
            ["op": "muscleVolume", "start": FX.date(2026, 1, 5, 0, 0, tz: FX.ba).timeIntervalSince1970, "end": FX.date(2026, 1, 12, 0, 0, tz: FX.ba).timeIntervalSince1970],
            ["op": "weeklyDirectSets", "muscle": "chest", "weeks": 2, "at": t(9)],
            ["op": "recentRecords", "days": 30, "at": t(9)],
            ["op": "addGoal", "alias": "g1", "exercise": "bench", "metric": "weight", "value": 62.5, "at": t(0)],
            ["op": "addGoal", "alias": "g2", "exercise": "bench", "metric": "repsAtWeight", "value": 12, "weight": 60, "at": t(0)],
            ["op": "goalProgress", "at": t(9)],
            ["op": "refreshGoals", "at": t(9)],
            ["op": "records", "exercise": "bench"],
        ]))

        // MARK: Stage 4–7 review regressions
        list.append(("plan with past from is clamped", base + [plan,
            ["op": "calendarWeek", "date": t(0), "at": t(10)],
            ["op": "setWeeklyPlan", "assignments": [String: String](), "from": t(0), "at": t(10)],
            ["op": "calendarWeek", "date": t(0), "at": t(10)],
            ["op": "plannedRoutine", "date": t(14)],
        ]))
        list.append(("latest saved plan wins", base + [
            ["op": "setWeeklyPlan", "assignments": ["2": "r"], "from": t(14), "at": t(0)],
            ["op": "setWeeklyPlan", "assignments": ["4": "r"], "from": t(1), "at": t(1)],
            ["op": "plannedRoutine", "date": t(21)],
            ["op": "plannedRoutine", "date": t(23)],
            ["op": "plannedRoutine", "date": t(2)],
        ]))
        list.append(("next planned workout", base + [plan,
            ["op": "nextPlanned", "at": t(0)],
        ] + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + [
            ["op": "nextPlanned", "at": t(0, 90)],
            ["op": "nextPlanned", "at": t(1)],
        ]))
        list.append(("records and series per context", base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
            ["op": "setContext", "log": "s2.0", "equipment": "Máquina convergente", "at": t(3)],
        ] + (0..<3).flatMap { i -> [Op] in [
            ["op": "updateSet", "log": "s2.0", "pos": i, "weight": 100, "reps": 10],
            ["op": "completeSet", "log": "s2.0", "pos": i, "at": t(3, 5)],
        ] } + [
            ["op": "finish", "session": "s2", "at": t(3, 40)],
            ["op": "contextClasses", "exercise": "bench"],
            ["op": "records", "exercise": "bench"],
            ["op": "records", "exercise": "bench", "classIndex": 1],
            ["op": "exerciseSeries", "exercise": "bench"],
            ["op": "exerciseSeries", "exercise": "bench", "classIndex": 1],
            ["op": "recentRecords", "days": 30, "at": t(4)],
            ["op": "linkContexts", "a": ["log": "s2.0"], "b": ["log": "s1.0"], "at": t(4)],
            ["op": "contextClasses", "exercise": "bench"],
            ["op": "exerciseSeries", "exercise": "bench"],
        ]))
        list.append(("to-date comparison", base + [plan]
            + [0, 2, 4, 7].enumerated().flatMap { i, d in perform("s\(i)", day: d, weight: 60, reps: [10, 10, 10]) } + [
            ["op": "comparison", "period": ["kind": "week"], "at": t(8)],
            ["op": "comparison", "period": ["kind": "last30Days"], "at": t(8)],
            ["op": "comparison", "period": ["kind": "calendarMonth"], "at": t(8)],
        ]))
        list.append(("recent records dedup", base + perform("s1", day: 0, weight: 60, reps: [12, 12, 12]) + [
            ["op": "startSession", "alias": "s2", "routine": "r", "at": t(3)],
        ] + [62.5, 65, 67.5].enumerated().flatMap { i, w -> [Op] in [
            ["op": "updateSet", "log": "s2.0", "pos": i, "weight": w, "reps": 10],
            ["op": "completeSet", "log": "s2.0", "pos": i, "at": t(3, 5)],
        ] } + [
            ["op": "finish", "session": "s2", "at": t(3, 40)],
            ["op": "recentRecords", "days": 30, "at": t(4)],
        ]))
        list.append(("import summary counts children of local sessions as conflicts", base + [
            ["op": "startSession", "alias": "s1", "routine": "r", "at": t(0)],
            ["op": "export", "blob": "b", "at": t(0, 1)],
            ["op": "removeSet", "log": "s1.0", "pos": 2],
            ["op": "finish", "session": "s1", "at": t(0, 30)],
            ["op": "import", "blob": "b"],
            ["op": "observeSets", "log": "s1.0"],
        ]))
        list.append(("goal dated by the record", base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10])
            + perform("s2", day: 3, weight: 65, reps: [8, 8, 8]) + [
            ["op": "addGoal", "alias": "g", "exercise": "bench", "metric": "weight", "value": 65, "at": t(1)],
            ["op": "refreshGoals", "at": t(20)],
        ]))
        list.append(("csv columns and formula neutralization", [
            exercise("weird", "=HYPERLINK(\"x\")", "weightReps", "dumbbell", "perSide", primary: ["biceps"]),
            ["op": "createRoutine", "alias": "r", "name": "R", "at": t(0)],
            ["op": "addRoutineExercise", "alias": "r.weird", "routine": "r", "exercise": "weird", "override": cfg(ProgressionConfig(targetSets: 1))],
        ] + perform("s1", day: 0, weight: 12.5, reps: [10], targetSets: 1) + [["op": "csv"]]))
        list.append(("muscle set goals and routine filter", base + perform("s1", day: 0, weight: 60, reps: [10, 10, 10]) + [
            ["op": "saveSettings", "patch": ["muscleSetGoals": ["chest": 10]]],
            ["op": "settings"],
            ["op": "muscleVolume", "start": t(-1), "end": t(2), "routine": "r"],
        ]))
        return list
    }
}
