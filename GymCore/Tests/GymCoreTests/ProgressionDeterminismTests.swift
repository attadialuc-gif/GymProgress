import Foundation
import Testing
@testable import GymCore

@Suite("Determinism and comparability")
struct ProgressionDeterminismTests {

    static let mixedHistory: [ExercisePerformance] = [
        Fx.perf(1, day: 0, weight: 57.5, reps: [12, 12, 12], rir: [2, 2, 2]),
        Fx.perf(2, day: 2, weight: 60, reps: [9, 8, 8], rir: [3, 2, 2]),
        Fx.perf(3, day: 4, weight: 60, reps: [11, 10, 9], rir: [2, 2, 2]),
        Fx.perf(4, day: 6, weight: 60, reps: [12, 12, 11], rir: [2, 2, 1]),
    ]

    @Test("Same input twice → identical output")
    func sameInputSameOutput() {
        let input = Fx.input(history: Self.mixedHistory)
        let a = ProgressionEngine.recommend(input)
        let b = ProgressionEngine.recommend(input)
        #expect(a == b)
    }

    @Test("Permuted history (sessions and sets) → identical output")
    func permutedInputSameOutput() {
        let reference = ProgressionEngine.recommend(Fx.input(history: Self.mixedHistory))
        let permutations: [[ExercisePerformance]] = [
            Self.mixedHistory.reversed(),
            [Self.mixedHistory[2], Self.mixedHistory[0], Self.mixedHistory[3], Self.mixedHistory[1]],
            Self.mixedHistory.map { perf in var p = perf; p.sets.reverse(); return p },
        ]
        for history in permutations {
            #expect(ProgressionEngine.recommend(Fx.input(history: history)) == reference)
        }
    }

    @Test("The engine never reads the clock: `generatedAt` is the injected now")
    func usesInjectedNow() {
        let now = Fx.day(9)
        let rec = ProgressionEngine.recommend(Fx.input(history: Self.mixedHistory, now: now))
        #expect(rec.generatedAt == now)
    }

    @Test("Change of machine → no automatic comparison, previous shown only as non-equivalent reference")
    func machineChangeIsNotComparable() {
        let machineA = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "Máquina A", loadMode: .total)
        let machineB = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "Máquina B", loadMode: .total)
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], context: machineA)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: machineB))

        #expect(rec.action == .needsInitialTarget)
        #expect(rec.reason == .noComparableHistoryInContext)
        #expect(rec.targetWeight == nil)
        #expect(rec.lastPerformance == nil)
        #expect(rec.nonEquivalentReference?.workingLoad == 60)
    }

    @Test("Change of variant → no automatic comparison")
    func variantChangeIsNotComparable() {
        let flat = ComparabilityContext(exerciseId: Fx.benchId, variantLabel: nil, loadMode: .total)
        let closeGrip = ComparabilityContext(exerciseId: Fx.benchId, variantLabel: "agarre cerrado", loadMode: .total)
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], context: flat)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: closeGrip))

        #expect(rec.action == .needsInitialTarget)
        #expect(rec.nonEquivalentReference != nil)
    }

    @Test("Change of load mode (total vs per side) → no automatic comparison")
    func loadModeChangeIsNotComparable() {
        let perSide = ComparabilityContext(exerciseId: Fx.benchId, loadMode: .perSide)
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2])]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: perSide))
        #expect(rec.action == .needsInitialTarget)
    }

    @Test("Other exercises never count, not even as a reference")
    func otherExerciseIsIgnored() {
        let squat = ComparabilityContext(exerciseId: Fx.squatId, loadMode: .total)
        let history = [Fx.perf(1, day: 0, weight: 100, reps: [12, 12, 12], rir: [2, 2, 2], context: squat)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history))
        #expect(rec.reason == .noComparableHistory)
        #expect(rec.nonEquivalentReference == nil)
    }

    @Test("Labels are compared case-, space- and accent-insensitively")
    func labelNormalization() {
        let a = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "  Máquina   A ", loadMode: .total)
        let b = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "maquina a", loadMode: .total)
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], context: a)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: b))
        #expect(rec.action == .increaseWeight)
    }

    @Test("Manual ComparabilityLink makes contexts comparable (symmetric and transitive)")
    func manualLink() {
        let a = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "A", loadMode: .total)
        let b = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "B", loadMode: .total)
        let c = ComparabilityContext(exerciseId: Fx.benchId, equipmentLabel: "C", loadMode: .total)
        let links = [
            ComparabilityLink(id: Fx.uuid(1), a: b, b: a, createdAt: Fx.day(0)),
            ComparabilityLink(id: Fx.uuid(2), a: b, b: c, createdAt: Fx.day(0)),
        ]
        let history = [Fx.perf(1, day: 0, weight: 60, reps: [12, 12, 12], rir: [2, 2, 2], context: a)]
        let rec = ProgressionEngine.recommend(Fx.input(history: history, context: c, links: links))

        #expect(rec.action == .increaseWeight)
        #expect(rec.targetWeight == 62.5)
        #expect(rec.nonEquivalentReference == nil)
    }
}
