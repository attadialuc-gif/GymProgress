import Foundation
import GymCore
import GymStore

// Usage:
//   swift run FixtureExporter export <dir>          writes the golden fixtures (crossplatform/fixtures)
//   swift run FixtureExporter verify-import <file>  imports an export made by another port into a
//                                                   fresh Swift store and re-exports it (exit 1 on loss)

@MainActor
func exportAll(to dir: URL) throws {
    let meta: [String: Any] = [
        "schemaVersion": GymSchema.currentVersion,
        "generator": "GymCore/Sources/FixtureExporter (Swift)",
        "dateEncoding": "seconds since 1970 (UTC), Double",
        "note": "Generated from the Swift implementation. Do not edit by hand; regenerate with `swift run FixtureExporter export`.",
    ]
    try writeJSON(meta, to: dir.appendingPathComponent("meta.json"))
    try writeJSON(EngineFixtures.cases(), to: dir.appendingPathComponent("engine_cases.json"))
    try writeJSON(EngineFixtures.helpers(), to: dir.appendingPathComponent("engine_helpers.json"))
    try writeJSON(CoreFixtures.metrics(), to: dir.appendingPathComponent("metrics.json"))
    try writeJSON(CoreFixtures.consistency(), to: dir.appendingPathComponent("consistency.json"))
    try writeJSON(CoreFixtures.parsing(), to: dir.appendingPathComponent("parsing.json"))

    var scenarios: [[String: Any]] = []
    for (name, ops) in Scenarios.all() {
        let runner = try ScenarioRunner()
        let observations = runner.run(ops)
        runner.cleanup()
        scenarios.append(["name": name, "ops": ops, "observations": observations])
    }
    try writeJSON(scenarios, to: dir.appendingPathComponent("store_scenarios.json"))

    // A complete export produced by Swift: other ports must import it without loss.
    let runner = try ScenarioRunner()
    var ops = Scenarios.perform("s1", day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], choice: Scenarios.choice("accept"))
    ops = [Scenarios.bench()] + Scenarios.routine() + ops
    ops += Scenarios.perform("s2", day: 3, weight: 62.5, reps: [8, 8, 7], choice: Scenarios.choice("modify", weight: 62.5, reps: [9, 9, 9]))
    ops += [["op": "seedCatalog"],
            ["op": "setWeeklyPlan", "assignments": ["2": "r", "5": "r"], "from": Scenarios.t(0), "at": Scenarios.t(0)],
            ["op": "addGoal", "alias": "g", "exercise": "bench", "metric": "weight", "value": 70, "at": Scenarios.t(0)],
            ["op": "linkContexts", "a": ["exercise": "bench", "equipment": "Smith", "loadMode": "total"], "b": ["exercise": "bench", "loadMode": "total"], "at": Scenarios.t(4)],
            ["op": "startSession", "alias": "open", "routine": "r", "at": Scenarios.t(6)],
            ["op": "decide", "log": "open.0", "choice": Scenarios.choice("accept"), "at": Scenarios.t(6, 1)],
            ["op": "export", "blob": "swift", "at": Scenarios.t(7)]]
    _ = runner.run(ops)
    let exportURL = dir.appendingPathComponent("export_from_swift.json")
    try runner.exportedBlob("swift").write(to: exportURL, options: .atomic)
    runner.cleanup()
    print("fixtures written to \(dir.path)")
}

@MainActor
func verifyImport(_ file: URL) throws -> Bool {
    let data = try Data(contentsOf: file)
    let incoming = try GymJSON.decoder.decode(GymDatabase.self, from: data)
    let repo = try JSONGymRepository()
    let summary = try ExportService(repository: repo).importJSON(data)
    var snapshot = repo.snapshot()
    snapshot.exportedAt = nil
    var expected = incoming
    expected.exportedAt = nil
    // Same records, same order rules (repository snapshots sort by id / date).
    let ok = snapshot.exercises.count == expected.exercises.count
        && snapshot.sessions.count == expected.sessions.count
        && snapshot.exerciseLogs.count == expected.exerciseLogs.count
        && snapshot.setLogs.count == expected.setLogs.count
        && snapshot.decisions.count == expected.decisions.count
        && snapshot.schedule.count == expected.schedule.count
        && snapshot.comparabilityLinks.count == expected.comparabilityLinks.count
        && snapshot.goals.count == expected.goals.count
        && Set(snapshot.setLogs) == Set(expected.setLogs)
        && Set(snapshot.exerciseLogs) == Set(expected.exerciseLogs)
        && Set(snapshot.sessions) == Set(expected.sessions)
        && Set(snapshot.decisions) == Set(expected.decisions)
        && Set(snapshot.exercises) == Set(expected.exercises)
        && snapshot.settings == expected.settings
    let again = try ExportService(repository: repo).importJSON(data)
    print("import summary: inserted=\(summary.inserted) conflicts=\(summary.conflicts) unchanged=\(summary.unchanged)")
    print("re-import: inserted=\(again.inserted) conflicts=\(again.conflicts) unchanged=\(again.unchanged)")
    print(ok && again.inserted == 0 ? "OK: no loss, no duplicates" : "FAIL")
    return ok && again.inserted == 0
}

let args = CommandLine.arguments
MainActor.assumeIsolated {
    do {
        switch args.dropFirst().first {
        case "export":
            try exportAll(to: URL(fileURLWithPath: args.count > 2 ? args[2] : "fixtures"))
        case "verify-import":
            if !(try verifyImport(URL(fileURLWithPath: args[2]))) { exit(1) }
        default:
            print("usage: FixtureExporter export <dir> | verify-import <file>")
            exit(2)
        }
    } catch {
        print("error: \(error)")
        exit(1)
    }
}
