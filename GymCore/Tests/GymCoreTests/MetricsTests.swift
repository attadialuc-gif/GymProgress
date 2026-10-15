import Foundation
import Testing
@testable import GymCore

@Suite("1RM estimation")
struct OneRepMaxTests {
    @Test("Epley golden values", arguments: [
        (100.0, 1, 100.0),
        (100.0, 5, 116.667),
        (60.0, 10, 80.0),
        (80.0, 3, 88.0),
    ] as [(Double, Int, Double)])
    func epley(weight: Double, reps: Int, expected: Double) throws {
        let value = try #require(OneRepMax.estimate(weight: weight, reps: reps, settings: .init(formula: .epley)))
        #expect(abs(value - expected) < 0.001)
    }

    @Test("Brzycki golden values", arguments: [
        (100.0, 1, 100.0),
        (100.0, 5, 112.5),
        (60.0, 10, 80.0),
    ] as [(Double, Int, Double)])
    func brzycki(weight: Double, reps: Int, expected: Double) throws {
        let value = try #require(OneRepMax.estimate(weight: weight, reps: reps, settings: .init(formula: .brzycki)))
        #expect(abs(value - expected) < 0.001)
    }

    @Test("Sets above the rep cap are excluded (default 10, configurable)")
    func repCap() {
        #expect(OneRepMax.estimate(weight: 60, reps: 11) == nil)
        #expect(OneRepMax.estimate(weight: 60, reps: 12, settings: .init(formula: .epley, maxReps: 12)) != nil)
    }

    @Test("Invalid input gives no estimate")
    func invalid() {
        #expect(OneRepMax.estimate(weight: 0, reps: 5) == nil)
        #expect(OneRepMax.estimate(weight: 60, reps: 0) == nil)
        #expect(OneRepMax.raw(weight: 60, reps: 37, formula: .brzycki) == nil)
    }

    @Test("Best per performance skips warm-ups, pending and user-excluded sets")
    func bestInPerformance() {
        var perf = Fx.perf(1, day: 0, weight: 100, reps: [5, 3])
        perf.sets.append(PerformedSet(index: 2, kind: .warmup, status: .completed, weight: 140, reps: 1))
        perf.sets.append(PerformedSet(index: 3, kind: .working, status: .pending, weight: 150, reps: 1))
        perf.sets.append(PerformedSet(index: 4, kind: .working, status: .completed, weight: 130, reps: 1, excludedFromEstimates: true))
        let best = OneRepMax.best(in: perf)
        #expect(best.map { abs($0 - 116.667) < 0.001 } == true)
    }
}

@Suite("Volume")
struct VolumeTests {
    @Test("External volume = Σ weight × reps of effective sets only")
    func externalVolume() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [10, 9, 8])
        perf.sets.append(PerformedSet(index: 3, kind: .warmup, status: .completed, weight: 40, reps: 10))
        perf.sets.append(PerformedSet(index: 4, kind: .working, status: .pending, weight: 60, reps: 10))
        perf.sets.append(PerformedSet(index: 5, kind: .dropSet, status: .completed, weight: 40, reps: 6))
        let v = Volume.of(perf)
        #expect(v.total == 60 * 27 + 40 * 6)
        #expect(v.effectiveSets == 4)
        #expect(v.reps == 33)
        #expect(v.basis == .external)
        #expect(v.perSide == nil)
    }

    @Test("Per side: per-side figure and total = 2 × per side")
    func perSideVolume() {
        let ctx = ComparabilityContext(exerciseId: Fx.curlId, loadMode: .perSide)
        let perf = Fx.perf(1, day: 0, weight: 12.5, reps: [10, 10], context: ctx)
        let v = Volume.of(perf)
        #expect(v.perSide == 250)
        #expect(v.total == 500)
    }

    static func pullUps(added: Double?, assistance: Double?) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: Fx.uuid(1), exerciseLogId: Fx.uuid(2), sessionStart: Fx.day(0),
            context: ComparabilityContext(exerciseId: Fx.pullUpId, loadMode: .total),
            measurement: .bodyweightReps,
            sets: [PerformedSet(index: 0, reps: 10, addedWeight: added, assistance: assistance),
                   PerformedSet(index: 1, reps: 8, addedWeight: added, assistance: assistance)]
        )
    }

    @Test("Body weight with known body weight: (bw + added − assistance) × reps")
    func bodyweightKnown() {
        #expect(Volume.of(Self.pullUps(added: 10, assistance: nil), bodyweight: 80).total == 90 * 18)
        #expect(Volume.of(Self.pullUps(added: nil, assistance: 20), bodyweight: 80).total == 60 * 18)
        #expect(Volume.of(Self.pullUps(added: 10, assistance: nil), bodyweight: 80).basis == .bodyweightIncluded)
    }

    @Test("Body weight without body weight: only external (added) load, flagged")
    func bodyweightUnknown() {
        let v = Volume.of(Self.pullUps(added: 10, assistance: nil), bodyweight: nil)
        #expect(v.total == 180)
        #expect(v.basis == .externalOnlyBodyweightUnknown)
        #expect(Volume.of(Self.pullUps(added: nil, assistance: nil)).total == 0)
    }

    @Test("Duration has no load volume, only time")
    func duration() {
        let perf = ExercisePerformance(
            sessionId: Fx.uuid(1), exerciseLogId: Fx.uuid(2), sessionStart: Fx.day(0),
            context: ComparabilityContext(exerciseId: Fx.plankId, loadMode: .total), measurement: .duration,
            sets: [PerformedSet(index: 0, seconds: 45), PerformedSet(index: 1, seconds: 40)]
        )
        let v = Volume.of(perf)
        #expect(v.basis == .notApplicable)
        #expect(v.timeUnderLoadSeconds == 85)
    }
}

@Suite("Muscle volume")
struct MuscleVolumeTests {
    @Test("Direct and indirect sets are reported separately; indirect uses the factor")
    func directAndIndirect() {
        let bench = MuscleWork(
            performance: Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10]),
            primary: [.chest],
            secondary: [MuscleInvolvement(muscle: .triceps), MuscleInvolvement(muscle: .frontDelts, factor: 0.3)]
        )
        let dips = MuscleWork(
            performance: Fx.perf(2, day: 2, weight: 0, reps: [10, 10]),
            primary: [.triceps],
            secondary: [MuscleInvolvement(muscle: .chest)]
        )
        let result = MuscleVolume.compute([bench, dips], indirectFactor: 0.5, calendar: Fx.utcCalendar)
        let byMuscle = Dictionary(uniqueKeysWithValues: result.map { ($0.muscle, $0) })

        #expect(byMuscle[.chest]?.directSets == 3)
        #expect(byMuscle[.chest]?.indirectSets == 1.0)
        #expect(byMuscle[.triceps]?.directSets == 2)
        #expect(byMuscle[.triceps]?.indirectSets == 1.5)
        #expect(byMuscle[.frontDelts]?.directSets == 0)
        #expect(abs((byMuscle[.frontDelts]?.indirectSets ?? 0) - 0.9) < 0.0001)
        #expect(byMuscle[.chest]?.frequencyDays == 1)
    }

    @Test("Warm-ups don't count; a muscle listed as primary and secondary counts once, as direct")
    func noDoubleCounting() {
        var perf = Fx.perf(1, day: 0, weight: 60, reps: [10])
        perf.sets.append(PerformedSet(index: 1, kind: .warmup, status: .completed, weight: 20, reps: 10))
        let work = MuscleWork(performance: perf, primary: [.chest], secondary: [MuscleInvolvement(muscle: .chest)])
        let result = MuscleVolume.compute([work], calendar: Fx.utcCalendar)
        #expect(result.count == 1)
        #expect(result[0].directSets == 1)
        #expect(result[0].indirectSets == 0)
    }
}

@Suite("Personal records")
struct PersonalRecordsTests {
    @Test("Real and estimated records are separated; first occurrence wins ties")
    func records() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [10, 10, 10]),
            Fx.perf(2, day: 3, weight: 62.5, reps: [8, 8, 7]),
            Fx.perf(3, day: 6, weight: 62.5, reps: [8, 8, 8]),
            Fx.perf(4, day: 9, weight: 60, reps: [12, 11, 10]),
        ]
        let summary = PersonalRecords.compute(history)

        #expect(summary.maxWeight?.value == 62.5)
        #expect(summary.maxWeight?.sessionId == Fx.uuid(0x1002))
        #expect(summary.maxWeight?.isEstimated == false)

        // 60×10 → 80; 62.5×8 → 79.17; 60×12 excluded (cap 10).
        #expect(summary.bestEstimatedOneRepMax?.value == 80)
        #expect(summary.bestEstimatedOneRepMax?.isEstimated == true)
        #expect(summary.bestEstimatedOneRepMax?.sessionId == Fx.uuid(0x1001))

        let at60 = summary.maxRepsAtWeight.first { $0.weight == 60 }
        #expect(at60?.reps == 12)
        #expect(at60?.sessionId == Fx.uuid(0x1004))

        #expect(summary.maxSessionVolume?.value == 1980, "\(String(describing: summary.maxSessionVolume))")
        #expect(!summary.history.isEmpty)
    }

    @Test("No history → no records (never invented)")
    func empty() {
        #expect(PersonalRecords.compute([]) == .empty)
    }

    @Test("Non-completed sessions don't create records")
    func onlyCompleted() {
        let summary = PersonalRecords.compute([Fx.perf(1, day: 0, weight: 200, reps: [1], status: .discarded)])
        #expect(summary.maxWeight == nil)
    }
}

@Suite("Trend classification")
struct TrendTests {
    @Test("Fewer than 3 values → no conclusion")
    func insufficient() {
        #expect(TrendAnalyzer.classify([100, 90]) == .insufficientData)
        #expect(TrendAnalyzer.classify([]) == .insufficientData)
    }

    @Test("Clear increase → progressing")
    func progressing() {
        #expect(TrendAnalyzer.classify([80, 82, 84, 86]) == .progressing)
    }

    @Test("Flat with low variability → possible plateau")
    func plateau() {
        #expect(TrendAnalyzer.classify([80, 80.5, 80, 80.2]) == .possiblePlateau)
    }

    @Test("Fluctuating results → stable, never a plateau")
    func fluctuating() {
        #expect(TrendAnalyzer.classify([80, 86, 79, 85, 80]) == .stable)
    }

    @Test("Decrease with a new low → declining")
    func declining() {
        #expect(TrendAnalyzer.classify([86, 84, 82, 80]) == .declining)
    }

    @Test("Dip right after a load increase is not 'declining' without a new low")
    func dipAfterIncrease() {
        #expect(TrendAnalyzer.classify([84, 79.17, 81.25]) != .declining)
    }

    @Test("Performances fall back to reps at constant load when e1RM is unavailable")
    func constantLoadFallback() {
        let history = [
            Fx.perf(1, day: 0, weight: 60, reps: [11, 11, 11]),
            Fx.perf(2, day: 2, weight: 60, reps: [12, 11, 11]),
            Fx.perf(3, day: 4, weight: 60, reps: [12, 12, 12]),
        ]
        #expect(TrendAnalyzer.classify(performances: history) == .progressing)
    }
}
