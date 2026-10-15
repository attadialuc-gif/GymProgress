import Foundation
import Testing
@testable import GymCore

/// Section 2.D: the eight mandatory cases. Config: 3 sets, 8–12 reps, RIR 2, +2.5 kg.
/// Every expected output is written by hand.
@Suite("2.D mandatory progression cases")
struct ProgressionMandatoryCasesTests {

    // MARK: Case 1 — top of range not reached

    @Test("Case 1: 60 kg × 10, 9, 8 → keep 60 kg, +1 rep on sets below the max")
    func case1_topOfRangeNotReached() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [10, 9, 8], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .increaseReps)
        #expect(rec.reason == .belowTopOfRange)
        #expect(rec.targetWeight == 60)
        #expect(rec.targetReps == [11, 10, 9])
        #expect(rec.reasonText.lowercased().contains("rango superior no alcanzado"))
        #expect(rec.lastPerformance?.amounts == [10, 9, 8])
        #expect(rec.lastPerformance?.workingLoad == 60)
    }

    @Test("Case 1 without RIR: same targets, but conditional on effort")
    func case1_withoutRIRIsConditional() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [10, 9, 8])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .increaseReps)
        #expect(rec.targetWeight == 60)
        #expect(rec.targetReps == [11, 10, 9])
        #expect(rec.confidence == .conditional)
        #expect(!rec.conditions.isEmpty)
    }

    // MARK: Case 2 — top of range reached in every set

    @Test("Case 2: 60 kg × 12, 12, 12 @ RIR 2 → 62.5 kg, reps back to 8, high confidence")
    func case2_topOfRangeReachedWithRIR() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .increaseWeight)
        #expect(rec.reason == .topOfRangeReached)
        #expect(rec.targetWeight == 62.5)
        #expect(rec.targetReps == [8, 8, 8])
        #expect(rec.confidence == .high)
        #expect(rec.conditions.isEmpty)
    }

    @Test("Case 2 without RIR: same suggestion, but conditional and explicit about the condition")
    func case2_topOfRangeReachedWithoutRIRIsConditional() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == 62.5)
        #expect(rec.targetReps == [8, 8, 8])
        #expect(rec.confidence == .conditional)
        #expect(rec.reasonText.contains("Podrías subir a 62,5 kg"))
        #expect(rec.reasonText.contains("buena técnica"))
        #expect(!rec.conditions.isEmpty)
    }

    @Test("Case 2 with RPE instead of RIR: RPE 8 ≈ RIR 2 counts as recorded effort")
    func case2_rpeCountsAsEffort() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12])
        perf.sets = perf.sets.map { var s = $0; s.rpe = 8; return s }
        let rec = ProgressionEngine.recommend(Fx.input(history: [perf]))

        #expect(rec.action == .increaseWeight)
        #expect(rec.confidence == .high)
    }

    // MARK: Case 3 — reps reached but not the target RIR

    @Test("Case 3: 60 kg × 12, 12, 12 @ RIR 0, 0, 1 → do not increase, explain effort")
    func case3_repsReachedButEffortAboveTarget() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [0, 0, 1])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .effortAboveTarget)
        #expect(rec.targetWeight == 60)
        #expect(rec.targetReps == [12, 12, 12])
        #expect(rec.reasonText.contains("esfuerzo"))
    }

    // MARK: Case 4 — performance lower than before

    @Test("Case 4: 12, 11, 10 then 10, 9, 8 at 60 kg → maintain, show history, no automatic reduction")
    func case4_performanceDropped() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [10, 9, 8], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .performanceDropped)
        #expect(rec.targetWeight == 60)
        #expect(rec.evidence.count == 2)
        #expect(rec.evidence.map(\.amounts) == [[10, 9, 8], [12, 11, 10]])
        // Aim to recover the previous session, never below the range minimum.
        #expect(rec.targetReps == [12, 11, 10])
    }

    @Test("Case 4: a single bad session below the minimum does not trigger reassess")
    func case4_singleSessionBelowMinimumIsNotReassess() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [9, 8, 7], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .maintain)
        #expect(rec.targetWeight == 60)
    }

    @Test("Case 4: sets below the minimum in 2 consecutive comparable sessions → reassess, load unchanged")
    func case4_twoConsecutiveSessionsBelowMinimumReassess() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 11, 10], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 60, reps: [9, 8, 7], rir: [2, 2, 2]),
            Fx.perf(3, day: 6, weight: 60, reps: [8, 7, 7], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .reassess)
        #expect(rec.reason == .repeatedBelowRepMin)
        // Reduction is the user's call: the engine keeps the current load as reference.
        #expect(rec.targetWeight == 60)
        #expect(rec.reasonText.contains("decidís vos"))
    }

    // MARK: Case 5 — new exercise without history

    @Test("Case 5: no sessions → insufficient data, no invented number")
    func case5_noHistory() {
        let rec = ProgressionEngine.recommend(Fx.input(history: []))

        #expect(rec.action == .needsInitialTarget)
        #expect(rec.reason == .noComparableHistory)
        #expect(rec.targetWeight == nil)
        #expect(rec.lastPerformance == nil)
        #expect(rec.evidence.isEmpty)
        #expect(rec.reasonText.contains("Todavía no hay datos suficientes"))
        let hasDigits = rec.reasonText.contains { $0.isNumber }
        #expect(!hasDigits)
    }

    @Test("Case 5: with a configured initial target → recommend it with reason 'objetivo inicial'")
    func case5_initialTargetConfigured() {
        var config = Fx.config
        config.initialWeight = 40
        let rec = ProgressionEngine.recommend(Fx.input(history: [], config: config))

        #expect(rec.action == .needsInitialTarget)
        #expect(rec.reason == .initialTarget)
        #expect(rec.targetWeight == 40)
        #expect(rec.targetReps == [8, 8, 8])
        #expect(rec.reasonText.lowercased().contains("objetivo inicial"))
    }

    // MARK: Case 6 — available increments change

    @Test("Case 6: next load respects increment and available weights", arguments: [
        (2.5, nil, 62.5),
        (5.0, nil, 65.0),
        (2.5, [60.0, 62.0, 64.0], 62.0),
        (1.0, [64.0, 60.0, 62.0, 62.0], 62.0),
    ] as [(Double, [Double]?, Double)])
    func case6_incrementsAndAvailableWeights(increment: Double, available: [Double]?, expected: Double) {
        var config = Fx.config
        config.increment = increment
        config.availableWeights = available
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config))

        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == expected)
    }

    @Test("Case 6: no heavier weight available → maintain with a notice")
    func case6_noHeavierWeightAvailable() {
        var config = Fx.config
        config.availableWeights = [50, 55, 60]
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, config: config))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .topOfRangeNoHeavierLoad)
        #expect(rec.targetWeight == 60)
        #expect(!rec.notes.isEmpty)
    }

    @Test("Case 6: changing the config does not alter the recorded history")
    func case6_configChangeDoesNotAlterHistory() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        var config = Fx.config
        let before = ProgressionEngine.recommend(Fx.input(history: history, config: config))
        config.increment = 5
        let after = ProgressionEngine.recommend(Fx.input(history: history, config: config))

        #expect(before.targetWeight == 62.5)
        #expect(after.targetWeight == 65)
        // The past performance is reported identically under both configs.
        #expect(before.lastPerformance == after.lastPerformance)
        #expect(history[0].sets.map(\.weight) == [60, 60, 60])
    }

    // MARK: Case 7 — incomplete sets

    @Test("Case 7: 12, 12 and the third set pending → no increase, complete all sets")
    func case7_thirdSetPending() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [12, 12], rir: [2, 2])
        perf.sets.append(PerformedSet(index: 2, kind: .working, status: .pending, weight: 60, reps: nil))
        let rec = ProgressionEngine.recommend(Fx.input(history: [perf]))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .incompleteSets)
        #expect(rec.targetWeight == 60)
        #expect(rec.targetReps.count == 3)
        // The pending set is not read as zero reps.
        #expect(rec.lastPerformance?.amounts == [12, 12])
    }

    @Test("Case 7: fewer completed sets than the target → no increase")
    func case7_fewerSetsThanTarget() {
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12], rir: [2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .incompleteSets)
        #expect(rec.targetReps == [12, 12, 8])
    }

    @Test("Case 7: a pending set with pre-filled reps is still not counted")
    func case7_pendingSetWithValuesIsIgnored() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [12, 12], rir: [2, 2])
        perf.sets.append(PerformedSet(index: 2, kind: .working, status: .pending, weight: 60, reps: 12, rir: 2))
        let rec = ProgressionEngine.recommend(Fx.input(history: [perf]))

        #expect(rec.action == .maintain)
        #expect(rec.reason == .incompleteSets)
    }

    @Test("Case 7: an exercise without completed sets is not a comparable session")
    func case7_noCompletedSetsIsNotComparable() {
        let pending = ExercisePerformance(
            sessionId: Fx.uuid(0x1001), exerciseLogId: Fx.uuid(0x2001), sessionStart: Fx.day(0),
            context: Fx.benchContext,
            sets: [
                PerformedSet(index: 0, status: .pending, weight: 60, reps: 12),
                PerformedSet(index: 1, kind: .warmup, status: .completed, weight: 40, reps: 10),
            ]
        )
        let rec = ProgressionEngine.recommend(Fx.input(history: [pending]))

        #expect(rec.action == .needsInitialTarget)
        #expect(rec.lastPerformance == nil)
    }

    // MARK: Case 8 — manual modification (engine side)

    @Test("Case 8: next recommendation uses what was actually performed, not the manual target")
    func case8_nextRecommendationUsesActualPerformance() {
        // The engine had suggested 62.5 × 8; the user modified the target to 61 kg and did 61 × 10, 9, 9.
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2]),
            Fx.perf(2, day: 3, weight: 61, reps: [10, 9, 9], rir: [2, 2, 2]),
        ]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))

        #expect(rec.lastPerformance?.workingLoad == 61)
        #expect(rec.targetWeight == 61)
        #expect(rec.action == .increaseReps)
        #expect(rec.targetReps == [11, 10, 10])
    }
}
