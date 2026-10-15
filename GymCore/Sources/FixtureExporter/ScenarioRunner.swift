import Foundation
import GymCore
import GymStore

/// Executes store scenarios written as data (an array of operations). Entities are named by
/// aliases so the same script can run in another language and be compared without depending on
/// random UUIDs: every UUID in an observation is replaced by its alias.
@MainActor
final class ScenarioRunner {
    typealias Op = [String: Any]

    private var stores: [String: (url: URL, repo: JSONGymRepository)] = [:]
    private var aliasOf: [UUID: String] = [:]
    private var idOf: [String: UUID] = [:]
    private var blobs: [String: Data] = [:]
    private var counters: [String: Int] = [:]
    let tz = TimeZone(identifier: FX.ba)!

    init() throws {
        try openStore("main", fresh: true)
        // Catalog exercises have fixed ids: pre-register them.
        if let catalog = try? ExerciseCatalog.bundled() {
            for e in catalog.exercises { register(e.uuid, "cat:\(e.catalogId)") }
        }
    }

    func exportedBlob(_ name: String) -> Data { blobs[name]! }

    func cleanup() {
        for s in stores.values { try? FileManager.default.removeItem(at: s.url) }
    }

    // MARK: Store handling

    private func openStore(_ name: String, fresh: Bool) throws {
        let url = stores[name]?.url ?? FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(name)-\(UUID().uuidString).json")
        if fresh { try? FileManager.default.removeItem(at: url) }
        stores[name] = (url, try JSONGymRepository(fileURL: url))
    }

    private func repo(_ op: Op) throws -> JSONGymRepository {
        let name = op["store"] as? String ?? "main"
        if stores[name] == nil { try openStore(name, fresh: true) }
        return stores[name]!.repo
    }

    private func workout(_ op: Op) throws -> WorkoutService { WorkoutService(repository: try repo(op), timeZone: tz) }
    private func routines(_ op: Op) throws -> RoutineService { RoutineService(repository: try repo(op)) }
    private func catalog(_ op: Op) throws -> ExerciseCatalogService { ExerciseCatalogService(repository: try repo(op)) }
    private func history(_ op: Op) throws -> HistoryService { HistoryService(repository: try repo(op)) }
    private func consistency(_ op: Op) throws -> ConsistencyService { ConsistencyService(repository: try repo(op), timeZone: tz) }
    private func stats(_ op: Op) throws -> StatsService { StatsService(repository: try repo(op), timeZone: tz) }
    private func exporter(_ op: Op) throws -> ExportService { ExportService(repository: try repo(op)) }

    // MARK: Aliases

    func register(_ id: UUID, _ alias: String) {
        if aliasOf[id] == nil { aliasOf[id] = alias }
        if idOf[alias] == nil { idOf[alias] = id }
    }

    private func id(_ alias: Any?) throws -> UUID {
        guard let a = alias as? String, let id = idOf[a] else { throw ScenarioError.unknownAlias("\(alias ?? "nil")") }
        return id
    }

    private func next(_ prefix: String) -> String {
        counters[prefix, default: 0] += 1
        return "\(prefix)\(counters[prefix]!)"
    }

    private func registerSessionLogs(_ session: UUID, alias: String, repo: JSONGymRepository) {
        for (i, log) in repo.exerciseLogs(sessionId: session).enumerated() {
            register(log.id, "\(alias).\(i)")
        }
    }

    // MARK: Values

    private func date(_ v: Any?) -> Date { Date(timeIntervalSince1970: (v as? Double) ?? Double(v as? Int ?? 0)) }
    private func double(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) }
    private func config(_ v: Any?) throws -> ProgressionConfig? {
        guard let v, !(v is NSNull) else { return nil }
        let data = try JSONSerialization.data(withJSONObject: v)
        return try GymJSON.decoder.decode(ProgressionConfig.self, from: data)
    }

    private func context(_ v: Any?, _ op: Op) throws -> ComparabilityContext {
        guard let d = v as? [String: Any] else { throw ScenarioError.badOp("context") }
        if let log = d["log"] { return try repo(op).exerciseLog(id: try id(log))!.context }
        let exerciseId = try id(d["exercise"])
        return ComparabilityContext(exerciseId: exerciseId, variantLabel: d["variant"] as? String, equipmentLabel: d["equipment"] as? String,
                                    loadMode: LoadMode(rawValue: d["loadMode"] as? String ?? "total")!)
    }

    private func period(_ v: Any?) throws -> StatsPeriod {
        guard let d = v as? [String: Any], let kind = d["kind"] as? String else { throw ScenarioError.badOp("period") }
        switch kind {
        case "week": return .week
        case "last30Days": return .last30Days
        case "calendarMonth": return .calendarMonth
        case "last90Days": return .last90Days
        case "calendarYear": return .calendarYear
        case "last12Months": return .last12Months
        default: return .custom(DateInterval(start: date(d["start"]), end: date(d["end"])))
        }
    }

    private func setAt(_ op: Op) throws -> SetLog {
        let sets = try repo(op).setLogs(exerciseLogId: try id(op["log"]))
        let pos = op["pos"] as? Int ?? 0
        guard pos < sets.count else { throw ScenarioError.badOp("pos \(pos)") }
        return sets[pos]
    }

    // MARK: Run

    func run(_ ops: [Op]) -> [[String: Any]] {
        var observations: [[String: Any]] = []
        for (step, op) in ops.enumerated() {
            let name = op["op"] as? String ?? "?"
            var entry: [String: Any] = ["step": step, "op": name]
            do {
                if let result = try execute(name, op) { entry["result"] = result }
            } catch let error as GymStoreError {
                entry["error"] = Self.errorName(error)
            } catch {
                entry["error"] = "unexpected: \(error)"
            }
            observations.append(entry)
        }
        return observations.map { normalize($0) as! [String: Any] }
    }

    static func errorName(_ error: GymStoreError) -> String {
        switch error {
        case .notFound: "notFound"
        case .sessionAlreadyOpen: "sessionAlreadyOpen"
        case .sessionNotOpen: "sessionNotOpen"
        case .hasHistory: "hasHistory"
        case .hasCompletedSets: "hasCompletedSets"
        case .missingValues: "missingValues"
        case .invalidValue: "invalidValue"
        case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
        case .invalidImport: "invalidImport"
        case .storage: "storage"
        }
    }

    /// Replaces every UUID string by its alias ("?" when unknown).
    private func normalize(_ value: Any) -> Any {
        switch value {
        case let s as String:
            if let u = UUID(uuidString: s) { return aliasOf[u] ?? "?" }
            return replaceUUIDs(in: s)
        case let a as [Any]: return a.map(normalize)
        case let d as [String: Any]:
            var out: [String: Any] = [:]
            for (k, v) in d { out[UUID(uuidString: k).map { aliasOf[$0] ?? "?" } ?? k] = normalize(v) }
            return out
        default: return value
        }
    }

    private func replaceUUIDs(in text: String) -> String {
        var result = text
        for (id, alias) in aliasOf where result.contains(id.uuidString) {
            result = result.replacingOccurrences(of: id.uuidString, with: alias)
        }
        return result
    }

    private func setSummary(_ s: SetLog) -> [String: Any] {
        var d: [String: Any] = ["index": s.index, "kind": s.kind.rawValue, "status": s.status.rawValue]
        d["weight"] = s.weight.map { $0 as Any } ?? NSNull()
        d["reps"] = s.reps.map { $0 as Any } ?? NSNull()
        d["seconds"] = s.seconds.map { $0 as Any } ?? NSNull()
        d["addedWeight"] = s.addedWeight.map { $0 as Any } ?? NSNull()
        d["assistance"] = s.assistance.map { $0 as Any } ?? NSNull()
        d["rir"] = s.rir.map { $0 as Any } ?? NSNull()
        d["rpe"] = s.rpe.map { $0 as Any } ?? NSNull()
        d["targetReps"] = s.targetReps.map { $0 as Any } ?? NSNull()
        d["targetSeconds"] = s.targetSeconds.map { $0 as Any } ?? NSNull()
        d["completedAt"] = s.completedAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull()
        return d
    }

    private func decisionJSON(_ d: RecommendationDecision?, log: UUID) -> Any {
        guard let d else { return NSNull() }
        register(d.id, "decision:\(aliasOf[log] ?? "?")")
        return json(d)
    }

    private func execute(_ name: String, _ op: Op) throws -> Any? {
        let at = date(op["at"])
        switch name {
        // MARK: catalog & routines
        case "createExercise":
            let progression = try config(op["progression"])
            let e = try catalog(op).createCustomExercise(
                name: op["name"] as! String,
                measurement: MeasurementType(rawValue: op["measurement"] as? String ?? "weightReps")!,
                equipment: Equipment(rawValue: op["equipment"] as? String ?? "barbell")!,
                loadMode: LoadMode(rawValue: op["loadMode"] as? String ?? "total")!,
                primaryMuscles: (op["primary"] as? [String] ?? []).compactMap(MuscleGroup.init(rawValue:)),
                secondaryMuscles: (op["secondary"] as? [[String: Any]] ?? []).map { MuscleInvolvement(muscle: MuscleGroup(rawValue: $0["muscle"] as! String)!, factor: double($0["factor"])) },
                increment: double(op["increment"]) ?? 2.5,
                availableWeights: (op["availableWeights"] as? [Any])?.compactMap(double),
                progression: progression
            )
            register(e.id, op["alias"] as! String)
            return json(e)
        case "seedCatalog":
            let r = try catalog(op).seed(try ExerciseCatalog.bundled())
            return ["inserted": r.inserted, "updated": r.updated]
        case "createRoutine":
            let r = try routines(op).createRoutine(name: op["name"] as! String, now: at)
            register(r.id, op["alias"] as! String)
            return json(r)
        case "createRoutineFromPreset":
            let preset = RoutinePreset.all.first { $0.id == op["preset"] as? String }!
            let r = try routines(op).createFromPreset(preset, now: at)
            register(r.id, op["alias"] as! String)
            for (i, item) in try repo(op).routineExercises(routineId: r.id).enumerated() { register(item.id, "\(op["alias"]!).\(i)") }
            return ["routine": json(r), "items": json(try repo(op).routineExercises(routineId: r.id))]
        case "addRoutineExercise":
            let item = try routines(op).addExercise(routineId: try id(op["routine"]), exerciseId: try id(op["exercise"]),
                                                     override: try config(op["override"]), restSeconds: op["restSeconds"] as? Int)
            register(item.id, op["alias"] as! String)
            return json(item)
        case "setSuperset":
            try routines(op).setSuperset(ids: try (op["items"] as! [String]).map { try id($0) }, group: op["group"] as? Int)
            return nil
        case "updateRoutineExerciseOverride":
            var item = try repo(op).routineExercise(id: try id(op["item"]))!
            item.progressionOverride = try config(op["override"])
            try routines(op).updateRoutineExercise(item)
            return json(try repo(op).routineExercise(id: item.id)!)
        case "duplicateRoutine":
            let copy = try routines(op).duplicateRoutine(id: try id(op["routine"]), now: at)
            register(copy.id, op["alias"] as! String)
            return ["routine": json(copy), "items": json(try repo(op).routineExercises(routineId: copy.id))]
        case "duplicateRoutineExercise":
            let dup = try routines(op).duplicateRoutineExercise(id: try id(op["item"]))
            register(dup.id, op["alias"] as! String)
            return json(try repo(op).routineExercises(routineId: dup.routineId))
        case "moveRoutineExercises":
            try routines(op).moveExercises(routineId: try id(op["routine"]), orderedIds: try (op["order"] as! [String]).map { try id($0) })
            return json(try repo(op).routineExercises(routineId: try id(op["routine"])))
        case "updateExerciseProgression":
            try catalog(op).updateProgression(exerciseId: try id(op["exercise"]), config: try config(op["config"])!)
            return json(try repo(op).exercise(id: try id(op["exercise"]))!)
        case "renameExercise":
            var e = try repo(op).exercise(id: try id(op["exercise"]))!
            e.name = op["name"] as! String
            try catalog(op).updateExercise(e)
            return nil
        case "setExerciseArchived":
            try catalog(op).setArchived(exerciseId: try id(op["exercise"]), op["archived"] as! Bool)
            return nil
        case "deleteExercise":
            try catalog(op).deleteExercise(id: try id(op["exercise"]))
            return nil
        case "renameRoutine":
            var r = try repo(op).routine(id: try id(op["routine"]))!
            r.name = op["name"] as! String
            try routines(op).updateRoutine(r)
            return nil
        case "setRoutineArchived":
            try routines(op).setArchived(routineId: try id(op["routine"]), op["archived"] as! Bool)
            return nil
        case "deleteRoutine":
            try routines(op).deleteRoutine(id: try id(op["routine"]))
            return nil
        case "routineExercises":
            return json(try repo(op).routineExercises(routineId: try id(op["routine"])))
        case "exercise":
            return jsonOrNull(try repo(op).exercise(id: try id(op["exercise"])))

        // MARK: sessions
        case "startSession":
            let routine = op["routine"].flatMap { $0 is NSNull ? nil : $0 }
            let s = try workout(op).startSession(routineId: try routine.map { try id($0) }, now: at)
            let alias = op["alias"] as! String
            register(s.id, alias)
            registerSessionLogs(s.id, alias: alias, repo: try repo(op))
            return json(s)
        case "addExerciseToSession":
            let log = try workout(op).addExercise(sessionId: try id(op["session"]), exerciseId: try id(op["exercise"]), now: at)
            register(log.id, op["alias"] as! String)
            return json(log)
        case "removeExercise":
            try workout(op).removeExercise(logId: try id(op["log"]))
            return nil
        case "moveExercises":
            try workout(op).moveExercises(sessionId: try id(op["session"]), orderedLogIds: try (op["order"] as! [String]).map { try id($0) })
            return try repo(op).exerciseLogs(sessionId: try id(op["session"])).map { aliasOf[$0.id] ?? "?" }
        case "pause": try workout(op).pause(sessionId: try id(op["session"]), now: at); return nil
        case "resume": try workout(op).resume(sessionId: try id(op["session"]), now: at); return nil
        case "finish": return json(try workout(op).finish(sessionId: try id(op["session"]), now: at))
        case "discard": try workout(op).discard(sessionId: try id(op["session"]), now: at); return nil
        case "setSessionAtypical": try workout(op).setSessionAtypical(sessionId: try id(op["session"]), op["value"] as! Bool, now: at); return nil
        case "setSessionNotes": try workout(op).setSessionNotes(sessionId: try id(op["session"]), notes: op["notes"] as! String, now: at); return nil
        case "setExerciseAtypical": try workout(op).setExerciseAtypical(logId: try id(op["log"]), op["value"] as! Bool); return nil
        case "setExerciseNotes": try workout(op).setExerciseNotes(logId: try id(op["log"]), notes: op["notes"] as! String); return nil
        case "openSession":
            return nn(try workout(op).openSession().map { aliasOf[$0.id] ?? "?" })
        case "observeSession":
            let s = try repo(op).session(id: try id(op["session"]))!
            return ["session": json(s), "elapsed": s.elapsed(at: at)] as [String: Any]

        // MARK: recommendation & decisions
        case "openExercise":
            let state = try workout(op).openExercise(logId: try id(op["log"]), now: at)
            return ["recommendation": json(state.recommendation), "decision": decisionJSON(state.decision, log: state.log.id),
                    "sets": state.sets.map(setSummary)] as [String: Any]
        case "decide":
            let choice: DecisionChoice
            let c = op["choice"] as! [String: Any]
            switch c["kind"] as! String {
            case "accept": choice = .accept
            case "ignore": choice = .ignore
            default: choice = .modify(weight: double(c["weight"]), reps: c["reps"] as? [Int] ?? [], seconds: c["seconds"] as? [Int])
            }
            let d = try workout(op).decide(logId: try id(op["log"]), choice: choice, now: at)
            return decisionJSON(d, log: try id(op["log"]))
        case "setInitialTarget":
            let d = try workout(op).setInitialTarget(logId: try id(op["log"]), weight: double(op["weight"]), reps: op["reps"] as? [Int] ?? [],
                                                     seconds: op["seconds"] as? [Int], now: at)
            return decisionJSON(d, log: try id(op["log"]))
        case "observeDecision":
            let logId = try id(op["log"])
            return decisionJSON(try repo(op).decision(exerciseLogId: logId), log: logId)
        case "setContext":
            return json(try workout(op).setContext(logId: try id(op["log"]), variantLabel: op["variant"] as? String, equipmentLabel: op["equipment"] as? String, now: at))
        case "switchContextEquivalent":
            return json(try workout(op).switchContextTreatingAsEquivalent(logId: try id(op["log"]), variantLabel: op["variant"] as? String, equipmentLabel: op["equipment"] as? String, now: at))
        case "linkContexts":
            let link = try workout(op).linkContexts(try context(op["a"], op), try context(op["b"], op), now: at)
            register(link.id, next("link:"))
            return json(link)
        case "observeLog":
            return json(try repo(op).exerciseLog(id: try id(op["log"]))!)
        case "preview":
            return jsonOrNull(try workout(op).previewRecommendation(exerciseId: try id(op["exercise"]), config: try config(op["config"]), now: at))
        case "previewRoutine":
            return try workout(op).previewRecommendations(routineId: try id(op["routine"]), now: at).map { item, exercise, rec in
                ["item": aliasOf[item.id] ?? "?", "exercise": aliasOf[exercise.id] ?? "?", "recommendation": json(rec)] as [String: Any]
            }
        case "copyPreviousLoads":
            try workout(op).copyPreviousLoads(logId: try id(op["log"]), allowNonEquivalent: op["allowNonEquivalent"] as? Bool ?? false, now: at)
            return try repo(op).setLogs(exerciseLogId: try id(op["log"])).map(setSummary)

        // MARK: sets
        case "updateSet":
            var s = try setAt(op)
            for key in ["weight", "addedWeight", "assistance", "rir", "rpe"] where op.keys.contains(key) {
                let v = double(op[key])
                switch key {
                case "weight": s.weight = v
                case "addedWeight": s.addedWeight = v
                case "assistance": s.assistance = v
                case "rir": s.rir = v
                default: s.rpe = v
                }
            }
            if op.keys.contains("reps") { s.reps = op["reps"] as? Int }
            if op.keys.contains("seconds") { s.seconds = op["seconds"] as? Int }
            if let kind = op["kind"] as? String { s.kind = SetKind(rawValue: kind)! }
            if op.keys.contains("weightText") { s.weight = WeightParser.parse(op["weightText"] as! String) }
            try workout(op).updateSet(s)
            return setSummary(try repo(op).setLog(id: s.id)!)
        case "addSet":
            let s = try workout(op).addSet(logId: try id(op["log"]), kind: SetKind(rawValue: op["kind"] as? String ?? "working")!)
            return setSummary(s)
        case "completeSet":
            let s = try setAt(op)
            return setSummary(try workout(op).completeSet(setId: s.id, now: at))
        case "reopenSet":
            try workout(op).reopenSet(setId: try setAt(op).id)
            return nil
        case "removeSet":
            try workout(op).removeSet(setId: try setAt(op).id)
            return try repo(op).setLogs(exerciseLogId: try id(op["log"])).map(setSummary)
        case "observeSets":
            return try repo(op).setLogs(exerciseLogId: try id(op["log"])).map(setSummary)
        case "restAdvice":
            let advice = try workout(op).restAdvice(afterCompleting: try setAt(op).id)
            return ["restSeconds": advice.restSeconds.map { $0 as Any } ?? NSNull(),
                    "next": nn(advice.nextExerciseLogId.map { aliasOf[$0] ?? "?" })] as [String: Any]

        // MARK: history & persistence
        case "reload":
            let name = op["store"] as? String ?? "main"
            try openStore(name, fresh: false)
            return nil
        case "exerciseHistory":
            return try history(op).exerciseHistory(exerciseId: try id(op["exercise"])).map { e in
                ["session": aliasOf[e.session.id] ?? "?", "log": aliasOf[e.log.id] ?? "?", "sets": e.sets.map(setSummary),
                 "decision": nn(e.decision?.kind.rawValue), "logName": e.log.snapshot.name,
                 "routineName": nn(e.session.routineNameSnapshot)] as [String: Any]
            }
        case "sessionSummaries":
            return try history(op).completedSessionSummaries(limit: op["limit"] as? Int).map { s in
                ["session": aliasOf[s.session.id] ?? "?", "exerciseNames": s.exerciseNames, "effectiveSets": s.effectiveSets,
                 "volume": s.volume, "duration": s.duration] as [String: Any]
            }
        case "sessionDigests":
            return json(try history(op).sessionDigests())
        case "counts":
            let db = try repo(op).snapshot()
            return ["exercises": db.exercises.count, "routines": db.routines.count, "routineExercises": db.routineExercises.count,
                    "schedule": db.schedule.count, "sessions": db.sessions.count, "exerciseLogs": db.exerciseLogs.count,
                    "setLogs": db.setLogs.count, "decisions": db.decisions.count, "links": db.comparabilityLinks.count, "goals": db.goals.count]
        case "saveSettings":
            var settings = try repo(op).settings()
            let patch = op["patch"] as! [String: Any]
            var dict = json(settings) as! [String: Any]
            for (k, v) in patch { dict[k] = v }
            settings = try GymJSON.decoder.decode(UserSettings.self, from: JSONSerialization.data(withJSONObject: dict))
            try repo(op).saveSettings(settings)
            return json(settings)
        case "settings":
            return json(try repo(op).settings())

        // MARK: export / import
        case "export":
            let data = try exporter(op).exportJSON(now: at)
            blobs[op["blob"] as! String] = data
            return nil
        case "import":
            let s = try exporter(op).importJSON(blobs[op["blob"] as! String]!)
            return ["inserted": s.inserted, "conflicts": s.conflicts, "unchanged": s.unchanged]
        case "importRaw":
            let data = try JSONSerialization.data(withJSONObject: op["json"]!)
            let s = try exporter(op).importJSON(data)
            return ["inserted": s.inserted, "conflicts": s.conflicts, "unchanged": s.unchanged]
        case "importText":
            let s = try exporter(op).importJSON(Data((op["text"] as! String).utf8))
            return ["inserted": s.inserted, "conflicts": s.conflicts, "unchanged": s.unchanged]
        case "snapshotEquals":
            var a = try repo(["store": op["a"] as Any]).snapshot()
            var b = try repo(["store": op["b"] as Any]).snapshot()
            a.exportedAt = nil
            b.exportedAt = nil
            return a == b
        case "csv":
            return try exporter(op).exportSetsCSV()
        case "mergeRaw":
            let db = try GymJSON.decoder.decode(GymDatabase.self, from: JSONSerialization.data(withJSONObject: op["json"]!))
            try repo(op).merge(db, includeSettings: op["includeSettings"] as? Bool ?? false)
            return nil
        case "scheduleEntries":
            return json(try repo(op).scheduleEntries())

        // MARK: consistency
        case "setWeeklyPlan":
            var assignments: [Int: UUID] = [:]
            for (k, v) in op["assignments"] as? [String: String] ?? [:] { assignments[Int(k)!] = try id(v) }
            let before = Set(try repo(op).scheduleEntries().map(\.id))
            try consistency(op).setWeeklyPlan(assignments, from: date(op["from"]), now: at)
            for e in try repo(op).scheduleEntries().filter({ !before.contains($0.id) }).sorted(by: { $0.weekday < $1.weekday }) {
                register(e.id, next("plan:"))
            }
            return nil
        case "calendarWeek":
            return try consistency(op).week(containing: date(op["date"]), now: at).map(calendarDay)
        case "calendarMonth":
            return try consistency(op).month(containing: date(op["date"]), now: at).map(calendarDay)
        case "weekSummary":
            let w = try consistency(op).weekSummary(now: at)
            return ["weekStart": w.weekStart.timeIntervalSince1970, "planned": w.planned, "validSessions": w.validSessions,
                    "weeklyGoal": w.weeklyGoal, "goalFraction": w.goalFraction, "goalMet": w.goalMet] as [String: Any]
        case "streak":
            let s = try consistency(op).streak(now: at)
            return ["result": json(s.result), "definition": s.definition] as [String: Any]
        case "plan":
            return Dictionary(uniqueKeysWithValues: try consistency(op).plan(asOf: date(op["asOf"])).map { (String($0.key), aliasOf[$0.value] ?? "?") })
        case "plannedRoutine":
            return nn(try consistency(op).plannedRoutine(on: date(op["date"])).map { aliasOf[$0] ?? "?" })
        case "nextPlanned":
            return nn(try consistency(op).nextPlannedWorkout(now: at).map { ["date": $0.date.timeIntervalSince1970, "routine": aliasOf[$0.routineId] ?? "?"] as [String: Any] })

        // MARK: stats
        case "periodIntervals":
            let p = try period(op["period"])
            let cal = try stats(op).calendar
            let comparable = p.comparableIntervals(now: at, calendar: cal)
            func iv(_ i: DateInterval) -> [Double] { [i.start.timeIntervalSince1970, i.end.timeIntervalSince1970] }
            return ["interval": iv(p.interval(now: at, calendar: cal)), "previous": iv(p.previousInterval(now: at, calendar: cal)),
                    "comparableCurrent": iv(comparable.current), "comparablePrevious": iv(comparable.previous)]
        case "comparison":
            let c = try stats(op).comparison(try period(op["period"]), now: at, routineId: try (op["routine"] as? String).map { try id($0) })
            return ["current": totalsJSON(c.current), "previous": totalsJSON(c.previous), "isToDate": c.isToDate] as [String: Any]
        case "totals":
            return totalsJSON(try stats(op).totals(in: DateInterval(start: date(op["start"]), end: date(op["end"])),
                                                   routineId: try (op["routine"] as? String).map { try id($0) }))
        case "contextClasses":
            return try stats(op).contextClasses(exerciseId: try id(op["exercise"])).map { c in
                ["label": c.label, "representative": json(c.representative), "contexts": c.contexts.map(\.sortKey).sorted(), "lastUsed": c.lastUsed.timeIntervalSince1970] as [String: Any]
            }
        case "exerciseSeries":
            let s = try stats(op)
            let classes = s.contextClasses(exerciseId: try id(op["exercise"]))
            let cls = (op["classIndex"] as? Int).map { classes[$0] }
            let interval = op["start"].map { _ in DateInterval(start: date(op["start"]), end: date(op["end"])) }
            return s.exerciseSeries(exerciseId: try id(op["exercise"]), in: interval, contextClass: cls,
                                    routineId: try (op["routine"] as? String).map { try id($0) }).map { p in
                ["log": aliasOf[p.exerciseLogId] ?? "?", "date": p.date.timeIntervalSince1970, "measurement": p.measurement.rawValue,
                 "loadMode": p.loadMode.rawValue, "workingLoad": p.workingLoad, "totalAmount": p.totalAmount, "bestSetAmount": p.bestSetAmount,
                 "estimatedOneRepMax": p.estimatedOneRepMax.map { $0 as Any } ?? NSNull(), "volume": p.volume,
                 "effectiveSets": p.effectiveSets, "isAtypical": p.isAtypical] as [String: Any]
            }
        case "muscleVolume":
            return json(try stats(op).muscleVolume(in: DateInterval(start: date(op["start"]), end: date(op["end"])),
                                                   routineId: try (op["routine"] as? String).map { try id($0) }))
        case "weeklyDirectSets":
            return try stats(op).weeklyDirectSets(muscle: MuscleGroup(rawValue: op["muscle"] as! String)!, weeks: op["weeks"] as! Int, now: at).map {
                ["weekStart": $0.weekStart.timeIntervalSince1970, "directSets": $0.directSets, "indirectSets": $0.indirectSets] as [String: Any]
            }
        case "records":
            let s = try stats(op)
            let classes = s.contextClasses(exerciseId: try id(op["exercise"]))
            let cls = (op["classIndex"] as? Int).map { classes[$0] }
            return json(s.records(exerciseId: try id(op["exercise"]), contextClass: cls))
        case "recentRecords":
            return try stats(op).recentRecords(days: op["days"] as! Int, now: at, limit: op["limit"] as? Int ?? 5).map { r in
                ["exercise": aliasOf[r.exerciseId] ?? "?", "exerciseName": r.exerciseName, "contextLabel": r.contextLabel, "record": json(r.record)] as [String: Any]
            }
        case "addGoal":
            let goal = Goal(exerciseId: try id(op["exercise"]), metric: GoalMetric(rawValue: op["metric"] as! String)!, value: double(op["value"])!,
                            weight: double(op["weight"]), targetDate: nil, createdAt: at)
            try repo(op).upsertGoal(goal)
            register(goal.id, op["alias"] as! String)
            return nil
        case "goalProgress":
            return try stats(op).goalProgress(now: at).map { g in
                ["goal": json(g.goal), "current": g.current.map { $0 as Any } ?? NSNull(), "fraction": g.fraction, "achieved": g.achieved,
                 "achievedOn": g.achievedOn.map { $0.timeIntervalSince1970 as Any } ?? NSNull()] as [String: Any]
            }
        case "refreshGoals":
            return json(try stats(op).refreshGoals(now: at))
        default:
            throw ScenarioError.badOp(name)
        }
    }

    private func calendarDay(_ d: CalendarDay) -> [String: Any] {
        ["date": d.date.timeIntervalSince1970, "status": d.status.rawValue, "plannedRoutine": nn(d.plannedRoutineId.map { aliasOf[$0] ?? "?" }),
         "plannedRoutineName": nn(d.plannedRoutineName), "sessions": d.sessionIds.map { aliasOf[$0] ?? "?" }.sorted(), "isToday": d.isToday]
    }

    private func totalsJSON(_ t: PeriodTotals) -> [String: Any] {
        ["validSessions": t.validSessions, "effectiveSets": t.effectiveSets, "volume": t.volume, "trainingDays": t.trainingDays]
    }
}

enum ScenarioError: Error {
    case unknownAlias(String)
    case badOp(String)
}
