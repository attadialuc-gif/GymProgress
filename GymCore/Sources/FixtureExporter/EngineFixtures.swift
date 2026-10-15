import Foundation
import GymCore

/// Progression engine fixtures: every case of ProgressionMandatoryCasesTests,
/// ProgressionDeterminismTests and ProgressionRulesTests, with the input and the full
/// `Recommendation` computed by the Swift engine.
enum EngineFixtures {
    static func engineCase(
        _ name: String,
        group: String? = nil,
        history: [ExercisePerformance],
        config: ProgressionConfig = FX.config,
        context: ComparabilityContext = FX.benchContext,
        measurement: MeasurementType = .weightReps,
        links: [ComparabilityLink] = [],
        now: Date = FX.day(7),
        excluding: UUID? = nil,
        timeZone: String = "UTC",
        locale: String = "es_AR"
    ) -> [String: Any] {
        let dto = EngineInputDTO(
            context: context, measurement: measurement, config: config, history: history, links: links,
            now: now, excludingSessionId: excluding, timeZone: timeZone, firstWeekday: 2, locale: locale,
            oneRepMax: .default, trendThresholds: .default
        )
        let output = ProgressionEngine.recommend(dto.input)
        var result: [String: Any] = ["name": name, "input": json(dto), "output": json(output)]
        if let group { result["group"] = group }
        return result
    }

    static func cases() -> [[String: Any]] {
        var c: [[String: Any]] = []
        let p: (Int, Int, Double, [Int], [Double?]?, ComparabilityContext, SessionStatus, Bool) -> ExercisePerformance = FX.perfP

        // MARK: 2.D mandatory cases
        c.append(engineCase("2D-1 top of range not reached", history: [p(1, 0, 60, [10, 9, 8], [2, 2, 2], FX.benchContext, .completed, false)]))
        c.append(engineCase("2D-1 without RIR is conditional", history: [p(1, 0, 60, [10, 9, 8], nil, FX.benchContext, .completed, false)]))
        c.append(engineCase("2D-2 top reached with RIR", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)]))
        c.append(engineCase("2D-2 top reached without RIR (conditional)", history: [p(1, 0, 60, [12, 12, 12], nil, FX.benchContext, .completed, false)]))
        var rpe = p(1, 0, 60, [12, 12, 12], nil, FX.benchContext, .completed, false)
        rpe.sets = rpe.sets.map { var s = $0; s.rpe = 8; return s }
        c.append(engineCase("2D-2 RPE counts as effort", history: [rpe]))
        c.append(engineCase("2D-3 effort above target", history: [p(1, 0, 60, [12, 12, 12], [0, 0, 1], FX.benchContext, .completed, false)]))
        c.append(engineCase("2D-4 performance dropped", history: [
            p(1, 0, 60, [12, 11, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [10, 9, 8], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("2D-4 single session below minimum is not reassess", history: [
            p(1, 0, 60, [12, 11, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [9, 8, 7], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("2D-4 two consecutive below minimum → reassess", history: [
            p(1, 0, 60, [12, 11, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [9, 8, 7], [2, 2, 2], FX.benchContext, .completed, false),
            p(3, 6, 60, [8, 7, 7], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("2D-5 no history", history: []))
        var initial = FX.config
        initial.initialWeight = 40
        c.append(engineCase("2D-5 initial target configured", history: [], config: initial))
        for (inc, available, label) in [(2.5, nil, "2.5"), (5.0, nil, "5"), (2.5, [60.0, 62.0, 64.0], "list 60/62/64"), (1.0, [64.0, 60.0, 62.0, 62.0], "unsorted list")] as [(Double, [Double]?, String)] {
            var cfg = FX.config
            cfg.increment = inc
            cfg.availableWeights = available
            c.append(engineCase("2D-6 increments \(label)", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], config: cfg))
        }
        var noHeavier = FX.config
        noHeavier.availableWeights = [50, 55, 60]
        c.append(engineCase("2D-6 no heavier weight available", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], config: noHeavier))
        var pending = p(1, 0, 60, [12, 12], [2, 2], FX.benchContext, .completed, false)
        pending.sets.append(PerformedSet(index: 2, kind: .working, status: .pending, weight: 60, reps: nil))
        c.append(engineCase("2D-7 third set pending", history: [pending]))
        c.append(engineCase("2D-7 fewer sets than target", history: [p(1, 0, 60, [12, 12], [2, 2], FX.benchContext, .completed, false)]))
        var pendingValues = p(1, 0, 60, [12, 12], [2, 2], FX.benchContext, .completed, false)
        pendingValues.sets.append(PerformedSet(index: 2, kind: .working, status: .pending, weight: 60, reps: 12, rir: 2))
        c.append(engineCase("2D-7 pending set with values ignored", history: [pendingValues]))
        let noCompleted = ExercisePerformance(
            sessionId: FX.uuid(0x1001), exerciseLogId: FX.uuid(0x2001), sessionStart: FX.day(0), context: FX.benchContext,
            sets: [PerformedSet(index: 0, status: .pending, weight: 60, reps: 12),
                   PerformedSet(index: 1, kind: .warmup, status: .completed, weight: 40, reps: 10)]
        )
        c.append(engineCase("2D-7 no completed sets is not comparable", history: [noCompleted]))
        c.append(engineCase("2D-8 next recommendation uses actual performance", history: [
            p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 61, [10, 9, 9], [2, 2, 2], FX.benchContext, .completed, false),
        ]))

        // MARK: Determinism (same input twice, permuted input) — every case in a group must match.
        let mixed = [
            p(1, 0, 57.5, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 2, 60, [9, 8, 8], [3, 2, 2], FX.benchContext, .completed, false),
            p(3, 4, 60, [11, 10, 9], [2, 2, 2], FX.benchContext, .completed, false),
            p(4, 6, 60, [12, 12, 11], [2, 2, 1], FX.benchContext, .completed, false),
        ]
        c.append(engineCase("determinism original", group: "mixed", history: mixed))
        c.append(engineCase("determinism same input again", group: "mixed", history: mixed))
        c.append(engineCase("determinism reversed sessions", group: "mixed", history: mixed.reversed()))
        c.append(engineCase("determinism shuffled sessions", group: "mixed", history: [mixed[2], mixed[0], mixed[3], mixed[1]]))
        c.append(engineCase("determinism reversed sets", group: "mixed", history: mixed.map { var x = $0; x.sets.reverse(); return x }))
        c.append(engineCase("determinism injected now", history: mixed, now: FX.day(9)))

        // MARK: Comparability
        let machineA = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "Máquina A", loadMode: .total)
        let machineB = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "Máquina B", loadMode: .total)
        c.append(engineCase("comparability machine change", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], machineA, .completed, false)], context: machineB))
        let closeGrip = ComparabilityContext(exerciseId: FX.benchId, variantLabel: "agarre cerrado", loadMode: .total)
        c.append(engineCase("comparability variant change", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], context: closeGrip))
        c.append(engineCase("comparability load mode change", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)],
                            context: ComparabilityContext(exerciseId: FX.benchId, loadMode: .perSide)))
        c.append(engineCase("comparability other exercise ignored", history: [p(1, 0, 100, [12, 12, 12], [2, 2, 2], ComparabilityContext(exerciseId: FX.squatId, loadMode: .total), .completed, false)]))
        let spaced = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "  Máquina   A ", loadMode: .total)
        let plain = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "maquina a", loadMode: .total)
        c.append(engineCase("comparability label normalization", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], spaced, .completed, false)], context: plain))
        let la = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "A", loadMode: .total)
        let lb = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "B", loadMode: .total)
        let lc = ComparabilityContext(exerciseId: FX.benchId, equipmentLabel: "C", loadMode: .total)
        c.append(engineCase("comparability manual link transitive", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], la, .completed, false)], context: lc,
                            links: [ComparabilityLink(id: FX.uuid(1), a: lb, b: la, createdAt: FX.day(0)),
                                    ComparabilityLink(id: FX.uuid(2), a: lb, b: lc, createdAt: FX.day(0))]))

        // MARK: Additional rules
        c.append(engineCase("long break 30 days", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], now: FX.day(30)))
        c.append(engineCase("long break boundary 21 days", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], now: FX.day(21)))
        c.append(engineCase("atypical excluded", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [6, 5, 5], [2, 2, 2], FX.benchContext, .completed, true),
        ]))
        c.append(engineCase("non completed sessions excluded", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 2, 80, [12, 12, 12], [2, 2, 2], FX.benchContext, .discarded, false),
            p(3, 3, 80, [12, 12, 12], [2, 2, 2], FX.benchContext, .active, false),
            p(4, 4, 80, [12, 12, 12], [2, 2, 2], FX.benchContext, .paused, false),
        ]))
        let today = p(2, 7, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)
        c.append(engineCase("current session excluded", history: [p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false), today], excluding: today.sessionId))
        c.append(engineCase("future sessions ignored", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 10, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false),
        ], now: FX.day(5)))
        var warm = p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)
        warm.sets.insert(PerformedSet(index: -1, kind: .warmup, status: .completed, weight: 40, reps: 10), at: 0)
        warm.sets.append(PerformedSet(index: 3, kind: .dropSet, status: .completed, weight: 40, reps: 5, rir: 0))
        c.append(engineCase("warm-up and drop sets ignored", history: [warm]))
        var twoSessions = FX.config
        twoSessions.requiredConsecutiveSessions = 2
        let one = [p(1, 0, 60, [11, 11, 10], [2, 2, 2], FX.benchContext, .completed, false), p(2, 3, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)]
        c.append(engineCase("consecutive sessions required: first at top", history: one, config: twoSessions))
        c.append(engineCase("consecutive sessions required: second at top", history: one + [p(3, 6, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], config: twoSessions))
        c.append(engineCase("extra sets ignored", history: [p(1, 0, 60, [12, 12, 12, 7], [2, 2, 2, 2], FX.benchContext, .completed, false)]))
        var mixedLoads = p(1, 0, 60, [12, 12], [2, 2], FX.benchContext, .completed, false)
        mixedLoads.sets.append(PerformedSet(index: 2, kind: .working, status: .completed, weight: 50, reps: 12, rir: 2))
        c.append(engineCase("mixed loads → incomplete", history: [mixedLoads]))
        c.append(engineCase("single session below minimum", history: [p(1, 0, 60, [9, 7, 6], [2, 2, 2], FX.benchContext, .completed, false)]))
        c.append(engineCase("reps held by effort", history: [p(1, 0, 60, [10, 9, 8], [1, 0, 0], FX.benchContext, .completed, false)]))
        c.append(engineCase("drop after increase is not a drop", history: [
            p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 62.5, [9, 8, 8], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("lower load is not a drop", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 55, [10, 9, 9], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("lighter after long break", history: [
            p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 30, 55, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
        ], now: FX.day(33)))
        c.append(engineCase("drop across long break ignored", history: [
            p(1, 0, 60, [12, 11, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 30, 60, [10, 9, 8], [2, 2, 2], FX.benchContext, .completed, false),
        ], now: FX.day(32)))
        c.append(engineCase("repeated below min across loads", history: [
            p(1, 0, 62.5, [9, 8, 7], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [8, 7, 7], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        func linkedLog(_ n: Int, _ ctx: ComparabilityContext, _ reps: [Int]) -> ExercisePerformance {
            ExercisePerformance(sessionId: FX.uuid(0x1001), exerciseLogId: FX.uuid(0x2000 + n), sessionStart: FX.day(0),
                                context: ctx, sets: FX.sets(weight: 60, reps: reps, rir: reps.map { _ in 2 }))
        }
        let abLinks = [ComparabilityLink(id: FX.uuid(1), a: la, b: lb, createdAt: FX.day(0))]
        c.append(engineCase("linked contexts in one session: top", history: [linkedLog(1, la, [12, 12, 12]), linkedLog(2, lb, [12, 12, 12])], config: twoSessions, context: la, links: abLinks))
        c.append(engineCase("linked contexts in one session: low", history: [linkedLog(1, la, [9, 8, 7]), linkedLog(2, lb, [8, 7, 7])], context: la, links: abLinks))
        let s1 = PerformedSet(index: 0, weight: 60, reps: 12, rir: 1)
        let s2 = PerformedSet(index: 0, weight: 60, reps: 12, rir: 3)
        let s3 = PerformedSet(index: 1, weight: 60, reps: 12, rir: 2)
        func single(_ sets: [PerformedSet]) -> ExercisePerformance {
            ExercisePerformance(sessionId: FX.uuid(0x1001), exerciseLogId: FX.uuid(0x2001), sessionStart: FX.day(0), context: FX.benchContext, sets: sets)
        }
        var twoSets = FX.config
        twoSets.targetSets = 2
        c.append(engineCase("set order total A", group: "set-order", history: [single([s1, s2, s3])], config: twoSets))
        c.append(engineCase("set order total B", group: "set-order", history: [single([s3, s2, s1])], config: twoSets))
        c.append(engineCase("rising reps is not plateau", history: [
            p(1, 0, 60, [10, 9, 9], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 2, 60, [10, 10, 9], [2, 2, 2], FX.benchContext, .completed, false),
            p(3, 4, 60, [11, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        var noTarget = FX.config
        noTarget.targetRIR = nil
        c.append(engineCase("no RIR target, no RIR → conditional", history: [p(1, 0, 60, [12, 12, 12], nil, FX.benchContext, .completed, false)], config: noTarget))
        c.append(engineCase("no RIR target, RIR recorded → high", history: [p(1, 0, 60, [12, 12, 12], [0, 0, 0], FX.benchContext, .completed, false)], config: noTarget))
        c.append(engineCase("partial RIR → conditional", history: [p(1, 0, 60, [12, 12, 12], [2, nil, 3], FX.benchContext, .completed, false)]))
        c.append(engineCase("inverted config sanitized", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)],
                            config: ProgressionConfig(targetSets: 0, repMin: 12, repMax: 8, targetRIR: 15, increment: -1)))
        let ma = ExercisePerformance(sessionId: FX.uuid(0x1001), exerciseLogId: FX.uuid(0x2001), sessionStart: FX.day(0), context: FX.benchContext, sets: FX.sets(weight: 60, reps: [12, 12], rir: [2, 2]))
        let mb = ExercisePerformance(sessionId: FX.uuid(0x1001), exerciseLogId: FX.uuid(0x2002), sessionStart: FX.day(0), context: FX.benchContext, sets: FX.sets(weight: 60, reps: [12], rir: [2]))
        c.append(engineCase("two logs in one session merged", history: [mb, ma]))
        let curl = ComparabilityContext(exerciseId: FX.curlId, loadMode: .perSide)
        var rack = FX.config
        rack.availableWeights = [20, 22, 24, 26]
        rack.increment = 1
        c.append(engineCase("dumbbells per side discrete rack", history: [p(1, 0, 22, [12, 12, 12], [2, 2, 2], curl, .completed, false)], config: rack, context: curl))
        let pullCtx = ComparabilityContext(exerciseId: FX.pullUpId, loadMode: .total)
        func pullUps(_ n: Int, _ d: Int, _ reps: [Int], added: Double? = nil, assistance: Double? = nil) -> ExercisePerformance {
            ExercisePerformance(sessionId: FX.uuid(0x1000 + n), exerciseLogId: FX.uuid(0x2000 + n), sessionStart: FX.day(d),
                                context: pullCtx, measurement: .bodyweightReps,
                                sets: reps.enumerated().map { i, r in PerformedSet(index: i, kind: .working, status: .completed, reps: r, addedWeight: added, assistance: assistance, rir: 2) })
        }
        var bwCfg = FX.config
        bwCfg.repMin = 5
        bwCfg.repMax = 10
        c.append(engineCase("body weight reps first", history: [pullUps(1, 0, [8, 7, 6])], config: bwCfg, context: pullCtx, measurement: .bodyweightReps))
        c.append(engineCase("body weight add load", history: [pullUps(1, 0, [12, 12, 12])], context: pullCtx, measurement: .bodyweightReps))
        c.append(engineCase("body weight reduce assistance", history: [pullUps(1, 0, [12, 12, 12], assistance: 20)], context: pullCtx, measurement: .bodyweightReps))
        let plankCtx = ComparabilityContext(exerciseId: FX.plankId, loadMode: .total)
        func plank(_ n: Int, _ d: Int, _ seconds: [Int]) -> ExercisePerformance {
            ExercisePerformance(sessionId: FX.uuid(0x1000 + n), exerciseLogId: FX.uuid(0x2000 + n), sessionStart: FX.day(d),
                                context: plankCtx, measurement: .duration,
                                sets: seconds.enumerated().map { i, s in PerformedSet(index: i, kind: .working, status: .completed, seconds: s, rir: 2) })
        }
        c.append(engineCase("duration progresses in seconds", history: [plank(1, 0, [45, 40, 60])], context: plankCtx, measurement: .duration))
        c.append(engineCase("duration top reached", history: [plank(1, 0, [60, 60, 65])], context: plankCtx, measurement: .duration))
        c.append(engineCase("trend needs three sessions", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 3, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("plateau note", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 2, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(3, 4, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("declining note", history: [
            p(1, 0, 60, [10, 10, 10], [2, 2, 2], FX.benchContext, .completed, false),
            p(2, 2, 60, [10, 10, 9], [2, 2, 2], FX.benchContext, .completed, false),
            p(3, 4, 60, [10, 9, 8], [2, 2, 2], FX.benchContext, .completed, false),
            p(4, 6, 60, [9, 8, 8], [2, 2, 2], FX.benchContext, .completed, false),
        ]))
        c.append(engineCase("en_US locale text", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)], locale: "en_US"))
        c.append(engineCase("Buenos Aires calendar long break boundary", history: [p(1, 0, 60, [12, 12, 12], [2, 2, 2], FX.benchContext, .completed, false)],
                            now: FX.day(21).addingTimeInterval(7 * 3600), timeZone: FX.ba))
        return c
    }

    /// Helpers used directly by the UI and services.
    static func helpers() -> [String: Any] {
        var tie = FX.perf(1, day: 0, weight: 60, reps: [10], rir: [2])
        tie.sets.append(PerformedSet(index: 1, kind: .working, status: .completed, weight: 62.5, reps: 8, rir: 2))
        let configs = [
            ProgressionConfig(targetSets: 0, repMin: 12, repMax: 8, targetRIR: 15, increment: -1),
            ProgressionConfig(targetSets: 25, repMin: 0, repMax: 200, targetRIR: -3, initialWeight: -5, increment: .nan, availableWeights: [60, 55, 60, -1],
                              requiredConsecutiveSessions: 0, reassessAfterDays: 0, secondsMin: 0, secondsMax: -5, secondsIncrement: 0),
            ProgressionConfig(availableWeights: []),
            FX.config,
        ]
        let loads: [(Double, Double, [Double]?)] = [(60, 2.5, nil), (60, 5, nil), (60, 1, [60, 62, 64]), (64, 1, [60, 62, 64]), (0.1, 0.2, nil), (61.234, 2.5, nil)]
        return [
            "workingLoad": [["performance": json(tie), "workingLoad": HistoryAnalyzer.workingLoad(of: tie) as Any]],
            "sanitize": configs.map { ["config": jsonSafe($0), "sanitized": json($0.sanitized())] },
            "nextLoad": loads.map { l in
                ["current": l.0, "increment": l.1, "availableWeights": l.2.map { $0 as Any } ?? NSNull(),
                 "next": LoadMath.nextLoad(after: l.0, increment: l.1, availableWeights: l.2).map { $0 as Any } ?? NSNull()]
            },
            "normalize": [0.1 + 0.2, 62.4999999, 1.0005, -0.0004, 1234.5678].map { ["value": $0, "normalized": LoadMath.normalized($0), "key": LoadMath.key($0)] },
        ]
    }

    /// NaN can't be JSON; encode it as the string "nan".
    static func jsonSafe(_ config: ProgressionConfig) -> Any {
        var dict: [String: Any] = [:]
        dict["strategy"] = config.strategy.rawValue
        dict["targetSets"] = config.targetSets
        dict["repMin"] = config.repMin
        dict["repMax"] = config.repMax
        dict["targetRIR"] = config.targetRIR.map { $0 as Any } ?? NSNull()
        dict["initialWeight"] = config.initialWeight.map { $0 as Any } ?? NSNull()
        dict["increment"] = config.increment.isNaN ? "nan" : config.increment as Any
        dict["availableWeights"] = config.availableWeights.map { $0 as Any } ?? NSNull()
        dict["requiredConsecutiveSessions"] = config.requiredConsecutiveSessions
        dict["reassessAfterDays"] = config.reassessAfterDays
        dict["secondsMin"] = config.secondsMin
        dict["secondsMax"] = config.secondsMax
        dict["secondsIncrement"] = config.secondsIncrement
        return dict
    }
}

private extension FX {
    /// Positional shorthand used by the case list above.
    static func perfP(_ n: Int, _ d: Int, _ w: Double, _ reps: [Int], _ rir: [Double?]?, _ ctx: ComparabilityContext, _ status: SessionStatus, _ atypical: Bool) -> ExercisePerformance {
        perf(n, day: d, weight: w, reps: reps, rir: rir, context: ctx, status: status, atypical: atypical)
    }
}
