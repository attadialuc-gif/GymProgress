import Foundation
import Testing
@testable import GymCore

/// Additional golden cases for the engine (section 13).
@Suite("Progression rules — additional golden cases")
struct ProgressionRulesTests {

    // MARK: Filtering

    @Test("Long break (> 21 days) → reassess, never increase")
    func longBreak() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, now: Fx.day(30)))
        #expect(rec.action == .reassess)
        #expect(rec.reason == .longBreak)
        #expect(rec.targetWeight == 60)
        #expect(rec.targetReps == [8, 8, 8])
        #expect(rec.reasonText.contains("30 días"))
    }

    @Test("Exactly 21 days is not a long break")
    func longBreakBoundary() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, now: Fx.day(21)))
        #expect(rec.action == .increaseWeight)
    }

    @Test("Atypical sessions are excluded from recommendations")
    func atypicalExcluded() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [6, 5, 5], rir: [2, 2, 2], atypical: true),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.lastPerformance?.amounts == [10, 10, 10])
        #expect(rec.action == .increaseReps)
        #expect(rec.targetReps == [11, 11, 11])
    }

    @Test("Active, paused and discarded sessions are not comparable")
    func nonCompletedSessionsExcluded() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 2, weight: 80, reps: [12, 12, 12], rir: [2, 2, 2], status: .discarded),
            Fx.perf(3, day: 3, weight: 80, reps: [12, 12, 12], rir: [2, 2, 2], status: .active),
            Fx.perf(4, day: 4, weight: 80, reps: [12, 12, 12], rir: [2, 2, 2], status: .paused),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.lastPerformance?.workingLoad == 60)
        #expect(rec.evidence.count == 1)
    }

    @Test("The current session is excluded so today's sets never change today's target")
    func currentSessionExcluded() {
        let today = Fx.perf(2, day: 7, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]), today]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, excludingSessionId: today.sessionId))
        #expect(rec.lastPerformance?.amounts == [10, 10, 10])
    }

    @Test("Sessions after `now` are ignored")
    func futureSessionsIgnored() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 10, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, now: Fx.day(5)))
        #expect(rec.lastPerformance?.amounts == [10, 10, 10])
    }

    @Test("Warm-up and drop sets do not feed progression")
    func warmupAndDropSetsIgnored() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])
        perf.sets.insert(PerformedSet(index: -1, kind: .warmup, status: .completed, weight: 40, reps: 10), at: 0)
        perf.sets.append(PerformedSet(index: 3, kind: .dropSet, status: .completed, weight: 40, reps: 5, rir: 0))
        let rec = ProgressionEngine.recommend(Fx.input(history: [perf]))
        #expect(rec.action == .increaseWeight)
        #expect(rec.lastPerformance?.amounts == [12, 12, 12])
    }

    // MARK: Rule details

    @Test("Required consecutive sessions = 2: first session at the top → repeat to confirm")
    func requiredConsecutiveSessions() {
        var config = Fx.config
        config.requiredConsecutiveSessions = 2
        let one = [
            Fx.perf(1, day: 0, weight: 60, reps: [11, 11, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]),
        ]
        let first = ProgressionEngine.recommend(Fx.input(history: one, config: config))
        #expect(first.action == .maintain)
        #expect(first.reason == .topOfRangeNeedsConfirmation)
        #expect(first.targetWeight == 60)

        let two = one + [Fx.perf(3, day: 6, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let second = ProgressionEngine.recommend(Fx.input(history: two, config: config))
        #expect(second.action == .increaseWeight)
        #expect(second.targetWeight == 62.5)
    }

    @Test("Extra sets beyond the target are ignored")
    func extraSetsIgnored() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12, 7], rir: [2, 2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .increaseWeight)
    }

    @Test("Mixed loads: fewer sets at the working load than the target → incomplete")
    func mixedLoads() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [12, 12], rir: [2, 2])
        perf.sets.append(PerformedSet(index: 2, kind: .working, status: .completed, weight: 50, reps: 12, rir: 2))
        let rec = ProgressionEngine.recommend(Fx.input(history: [perf]))
        #expect(rec.action == .maintain)
        #expect(rec.reason == .incompleteSets)
        #expect(rec.targetWeight == 60)
        #expect(rec.reasonText.contains("misma carga"))
    }

    @Test("Working load ties resolve to the heavier load")
    func workingLoadTie() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [10], rir: [2])
        perf.sets.append(PerformedSet(index: 1, kind: .working, status: .completed, weight: 62.5, reps: 8, rir: 2))
        #expect(HistoryAnalyzer.workingLoad(of: perf) == 62.5)
    }

    @Test("Single session below the minimum → maintain, aim for the minimum")
    func singleSessionBelowMinimum() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [9, 7, 6], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .maintain)
        #expect(rec.reason == .belowRepMin)
        #expect(rec.targetReps == [9, 8, 8])
    }

    @Test("Inside the range but RIR already below target → hold reps, don't push")
    func repsHeldByEffort() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [10, 9, 8], rir: [1, 0, 0])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .maintain)
        #expect(rec.reason == .repsHeldByEffort)
        #expect(rec.targetReps == [10, 9, 8])
    }

    @Test("Reps after a load increase drop as expected: not a performance drop")
    func dropAfterIncreaseIsNotADrop() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 62.5, reps: [9, 8, 8], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetWeight == 62.5)
        #expect(rec.targetReps == [10, 9, 9])
    }

    @Test("A lower load is the user's choice, never a 'drop': progress from the new load")
    func lowerLoadIsNotADrop() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 55, reps: [10, 9, 9], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetWeight == 55)
        #expect(rec.targetReps == [11, 10, 10])
    }

    @Test("Review finding: returning lighter after a long break → add reps, no false drop")
    func lighterAfterLongBreak() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]),
            Fx.perf(2, day: 30, weight: 55, reps: [10, 10, 10], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, now: Fx.day(33)))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetWeight == 55)
        #expect(rec.targetReps == [11, 11, 11])
    }

    @Test("Same-load drop is ignored when the previous session was before a long break")
    func dropAcrossLongBreakIgnored() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 30, weight: 60, reps: [10, 9, 8], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, now: Fx.day(32)))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetReps == [11, 10, 9])
    }

    @Test("Review finding: below the minimum in 2 consecutive sessions at different loads → reassess")
    func repeatedBelowMinAcrossLoads() {
        let history = [
            Fx.perf(1, day: 0, weight: 62.5, reps: [9, 8, 7], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [8, 7, 7], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .reassess)
        #expect(rec.reason == .repeatedBelowRepMin)
        #expect(rec.targetWeight == 60)
    }

    @Test("Review finding: two linked machines in ONE session are one session, not two")
    func linkedContextsSameSessionAreOneSession() {
        let a = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "A", loadMode: .total)
        let b = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "B", loadMode: .total)
        let links = [ComparabilityLink(id: Fx.uuid(1), a: a, b: b, createdAt: Fx.day(0))]
        func log(_ n: Int, _ ctx: ComparabilityContext, _ reps: [Int]) -> ExercisePerformance {
            ExercisePerformance(sessionId: Fx.uuid(0x1001), exerciseLogId: Fx.uuid(0x2000 + n), sessionStart: Fx.day(0),
                                context: ctx, sets: Fx.sets(weight: 60, reps: reps, rir: reps.map { _ in 2 }))
        }

        var config = Fx.config
        config.requiredConsecutiveSessions = 2
        let top = ProgressionEngine.recommend(Fx.input(history: [log(1, a, [12, 12, 12]), log(2, b, [12, 12, 12])], config: config, context: a, links: links))
        #expect(top.reason == .topOfRangeNeedsConfirmation)
        #expect(top.evidence.count == 1)

        let low = ProgressionEngine.recommend(Fx.input(history: [log(1, a, [9, 8, 7]), log(2, b, [8, 7, 7])], context: a, links: links))
        #expect(low.action != .reassess)
    }

    @Test("Review finding: sets that differ only in RIR order deterministically (permuted input)")
    func setOrderIsTotal() {
        let s1 = PerformedSet(index: 0, weight: 60, reps: 12, rir: 1)
        let s2 = PerformedSet(index: 0, weight: 60, reps: 12, rir: 3)
        let s3 = PerformedSet(index: 1, weight: 60, reps: 12, rir: 2)
        func perf(_ sets: [PerformedSet]) -> ExercisePerformance {
            ExercisePerformance(sessionId: Fx.uuid(0x1001), exerciseLogId: Fx.uuid(0x2001), sessionStart: Fx.day(0), context: Fx.benchContext, sets: sets)
        }
        var config = Fx.config
        config.targetSets = 2
        let r1 = ProgressionEngine.recommend(Fx.input(history: [perf([s1, s2, s3])], config: config))
        let r2 = ProgressionEngine.recommend(Fx.input(history: [perf([s3, s2, s1])], config: config))
        #expect(r1 == r2)
    }

    @Test("Review finding: reps rising inside the range is not a 'possible plateau'")
    func risingRepsIsNotPlateau() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 9, 9], rir: [2, 2, 2]),
            Fx.perf(2, day: 2, weight: 60, reps: [10, 10, 9], rir: [2, 2, 2]),
            Fx.perf(3, day: 4, weight: 60, reps: [11, 10, 10], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.trend == .progressing)
        #expect(!rec.notes.contains { $0.contains("estancamiento") })
    }

    @Test("No RIR target configured and RIR not recorded → still conditional")
    func noTargetNoRIRIsConditional() {
        var config = Fx.config
        config.targetRIR = nil
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config))
        #expect(rec.action == .increaseWeight)
        #expect(rec.confidence == .conditional)
    }

    @Test("No RIR target configured and RIR recorded → high confidence")
    func noTargetWithRIRIsHigh() {
        var config = Fx.config
        config.targetRIR = nil
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [0, 0, 0])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config))
        #expect(rec.action == .increaseWeight)
        #expect(rec.confidence == .high)
    }

    @Test("Partially recorded RIR (none below target) → conditional")
    func partialRIRIsConditional() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, nil, 3])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.action == .increaseWeight)
        #expect(rec.confidence == .conditional)
    }

    @Test("Inverted user config is sanitized instead of crashing")
    func sanitizedConfig() {
        let config = ProgressionConfig(targetSets: 0, repMin: 12, repMax: 8, targetRIR: 15, increment: -1)
        let s = config.sanitized()
        #expect(s.targetSets == 1)
        #expect(s.repMin == 12)
        #expect(s.repMax == 12)
        #expect(s.targetRIR == 10)
        #expect(s.increment == 2.5)
    }

    @Test("Two logs of the same exercise in one session are merged")
    func mergedLogs() {
        let a = ExercisePerformance(
            sessionId: Fx.uuid(0x1001), exerciseLogId: Fx.uuid(0x2001), sessionStart: Fx.day(0),
            context: Fx.benchContext, sets: Fx.sets(weight: 60, reps: [12, 12], rir: [2, 2])
        )
        let b = ExercisePerformance(
            sessionId: Fx.uuid(0x1001), exerciseLogId: Fx.uuid(0x2002), sessionStart: Fx.day(0),
            context: Fx.benchContext, sets: Fx.sets(weight: 60, reps: [12], rir: [2])
        )
        let rec = ProgressionEngine.recommend(Fx.input(history: [b, a]))
        #expect(rec.lastPerformance?.amounts == [12, 12, 12])
        #expect(rec.action == .increaseWeight)
    }

    // MARK: Equipment variants

    @Test("Dumbbells per side with a discrete rack: 22 kg → next available 24 kg")
    func dumbbellsPerSide() {
        let ctx = ComparabilityContext(exerciseId: Fx.curlId, loadMode: .perSide)
        var config = Fx.config
        config.availableWeights = [20, 22, 24, 26]
        config.increment = 1
        let history = [Fx.perf(1, day: 0, weight: 22, reps: [12, 12, 12], rir: [2, 2, 2], context: ctx)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config, context: ctx))
        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == 24)
        #expect(rec.reasonText.contains("24 kg por lado"))
    }

    static let pullUpContext = ComparabilityContext(exerciseId: Fx.pullUpId, loadMode: .total)

    static func pullUps(_ n: Int, day: Int, reps: [Int], added: Double? = nil, assistance: Double? = nil) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: Fx.uuid(0x1000 + n), exerciseLogId: Fx.uuid(0x2000 + n), sessionStart: Fx.day(day),
            context: pullUpContext, measurement: .bodyweightReps,
            sets: reps.enumerated().map { i, r in
                PerformedSet(index: i, kind: .working, status: .completed, reps: r, addedWeight: added, assistance: assistance, rir: 2)
            }
        )
    }

    @Test("Body weight: reps first inside the range")
    func bodyweightRepsFirst() {
        let history = [Self.pullUps(1, day: 0, reps: [8, 7, 6])]
        var config = Fx.config
        config.repMin = 5
        config.repMax = 10
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config, context: Self.pullUpContext, measurement: .bodyweightReps))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetWeight == 0)
        #expect(rec.targetReps == [9, 8, 7])
    }

    @Test("Body weight at the top → add load (with note about needing a belt)")
    func bodyweightAddLoad() {
        let history = [Self.pullUps(1, day: 0, reps: [12, 12, 12])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: Self.pullUpContext, measurement: .bodyweightReps))
        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == 2.5)
        #expect(rec.targetReps == [8, 8, 8])
        #expect(!rec.notes.isEmpty)
        #expect(rec.reasonText.contains("peso corporal +2,5 kg"))
    }

    @Test("Assisted body weight at the top → reduce assistance")
    func bodyweightReduceAssistance() {
        let history = [Self.pullUps(1, day: 0, reps: [12, 12, 12], assistance: 20)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: Self.pullUpContext, measurement: .bodyweightReps))
        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == -17.5)
        #expect(rec.reasonText.contains("17,5 kg de asistencia"))
    }

    static let plankContext = ComparabilityContext(exerciseId: Fx.plankId, loadMode: .total)

    static func plank(_ n: Int, day: Int, seconds: [Int]) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: Fx.uuid(0x1000 + n), exerciseLogId: Fx.uuid(0x2000 + n), sessionStart: Fx.day(day),
            context: plankContext, measurement: .duration,
            sets: seconds.enumerated().map { i, s in
                PerformedSet(index: i, kind: .working, status: .completed, seconds: s, rir: 2)
            }
        )
    }

    @Test("Duration progresses in seconds")
    func durationProgressesInSeconds() {
        let history = [Self.plank(1, day: 0, seconds: [45, 40, 60])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: Self.plankContext, measurement: .duration))
        #expect(rec.action == .increaseReps)
        #expect(rec.targetSeconds == [50, 45, 60])
        #expect(rec.targetReps.isEmpty)
    }

    @Test("Duration at the top → maintain and suggest a harder variant (no automatic change)")
    func durationTop() {
        let history = [Self.plank(1, day: 0, seconds: [60, 60, 65])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: Self.plankContext, measurement: .duration))
        #expect(rec.action == .maintain)
        #expect(rec.reason == .durationTopReached)
        #expect(rec.targetSeconds == [60, 60, 60])
    }

    // MARK: Trend inside the recommendation

    @Test("With fewer than 3 comparable sessions no trend is declared")
    func trendNeedsThreeSessions() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.trend == .insufficientData)
        #expect(rec.notes.isEmpty)
    }

    @Test("Flat results over 3 sessions → possible plateau note (never an automatic change)")
    func plateauNote() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 2, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
            Fx.perf(3, day: 4, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.trend == .possiblePlateau)
        #expect(rec.action == .increaseReps)
        #expect(rec.notes.contains { $0.contains("Posible estancamiento") })
    }
}
