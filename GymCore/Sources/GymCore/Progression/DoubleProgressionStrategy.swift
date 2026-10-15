import Foundation

/// Default strategy: double progression (reps first inside the range, then load).
/// Rule order and rationale: docs/FORMULAS.md §8.2 and docs/DECISIONS.md (D-010…D-016).
public struct DoubleProgressionStrategy: ProgressionStrategy {
    public let kind: ProgressionStrategyKind = .doubleProgression

    public init() {}

    enum Effort {
        /// Some recorded RIR is below the target.
        case belowTarget
        /// All sets recorded and at or above the target.
        case meetsTarget
        /// All sets recorded, no target configured.
        case recordedNoTarget
        /// Missing for at least one set (and none below target).
        case unknown

        var isConfirmed: Bool { self == .meetsTarget || self == .recordedNoTarget }
    }

    public func recommend(_ input: ProgressionInput) -> Recommendation {
        let config = input.config.sanitized()
        let m = input.measurement
        let text = RecommendationText(locale: input.locale, measurement: m, loadMode: input.context.loadMode, config: config)
        let comparable = HistoryAnalyzer.comparable(input)
        let summaries = comparable.map(HistoryAnalyzer.summary(of:))

        let top = m == .duration ? config.secondsMax : config.repMax
        let bottom = m == .duration ? config.secondsMin : config.repMin
        let step = m == .duration ? config.secondsIncrement : 1
        let sets = config.targetSets

        var rec = Recommendation(
            strategy: kind,
            action: .maintain,
            reason: .noComparableHistory,
            confidence: .high,
            measurement: m,
            targetWeight: nil,
            targetReps: [],
            targetSeconds: nil,
            target: SessionTarget(config: config),
            reasonText: "",
            conditions: [],
            notes: [],
            context: input.context,
            lastPerformance: summaries.first,
            evidence: Array(summaries.prefix(5)),
            nonEquivalentReference: nil,
            trend: TrendAnalyzer.classify(
                performances: comparable.reversed(),
                oneRepMax: input.oneRepMax,
                thresholds: input.trendThresholds
            ),
            generatedAt: input.now
        )

        func setAmounts(_ amounts: [Int]) {
            if m == .duration {
                rec.targetSeconds = amounts
                rec.targetReps = []
            } else {
                rec.targetReps = amounts
                rec.targetSeconds = nil
            }
        }

        // Rule 1 — no comparable history.
        guard let last = comparable.first, let lastSummary = summaries.first else {
            let reference = HistoryAnalyzer.nonEquivalentReference(input).map(HistoryAnalyzer.summary(of:))
            rec.nonEquivalentReference = reference
            rec.action = .needsInitialTarget
            if let initial = config.initialWeight {
                rec.reason = .initialTarget
                rec.targetWeight = LoadMath.normalized(initial)
                setAmounts(Array(repeating: bottom, count: sets))
                rec.reasonText = text.initialTarget(initial)
            } else {
                rec.reason = reference == nil ? .noComparableHistory : .noComparableHistoryInContext
                rec.reasonText = reference == nil ? text.noHistory : text.noHistoryInContext
            }
            return rec
        }

        let load = lastSummary.workingLoad
        rec.targetWeight = load
        appendTrendNotes(&rec, text: text)

        // Rule 2 — long break.
        let days = Self.daysBetween(last.sessionStart, input.now, calendar: input.calendar)
        if days > config.reassessAfterDays {
            rec.action = .reassess
            rec.reason = .longBreak
            setAmounts(Array(repeating: bottom, count: sets))
            rec.reasonText = text.longBreak(days: days, weight: load)
            return rec
        }

        let evaluated = HistoryAnalyzer.evaluatedSets(of: last, limit: sets)
        let amounts = evaluated.map { $0.amount(for: m) }

        // Rule 3 — incomplete sets (fewer effective sets at the working load than the target).
        if evaluated.count < sets {
            rec.action = .maintain
            rec.reason = .incompleteSets
            let kept = amounts.map { min(max($0, bottom), top) }
            setAmounts(kept + Array(repeating: bottom, count: sets - kept.count))
            rec.reasonText = text.incompleteSets(
                done: evaluated.count,
                weight: load,
                mixedLoads: last.progressionSets.count >= sets
            )
            return rec
        }

        let effort = Self.assessEffort(evaluated, targetRIR: config.targetRIR)
        let allTop = amounts.allSatisfy { $0 >= top }

        if allTop {
            // Duration: progress in seconds only; beyond the range the user picks a harder variant.
            if m == .duration {
                rec.action = .maintain
                rec.reason = .durationTopReached
                setAmounts(Array(repeating: top, count: sets))
                rec.reasonText = text.durationTopReached(weight: load)
                return rec
            }

            // Rule 5 — reps reached but effort above target: never increase.
            if effort == .belowTarget {
                rec.action = .maintain
                rec.reason = .effortAboveTarget
                setAmounts(Array(repeating: top, count: sets))
                rec.reasonText = text.effortAboveTarget(weight: load)
                return rec
            }

            // Rule 4 — consecutive sessions at the top of the range.
            let streak = Self.topStreak(comparable, load: load, sets: sets, top: top, measurement: m)
            if streak < config.requiredConsecutiveSessions {
                rec.action = .maintain
                rec.reason = .topOfRangeNeedsConfirmation
                setAmounts(Array(repeating: top, count: sets))
                rec.reasonText = text.needsConfirmation(achieved: streak, required: config.requiredConsecutiveSessions, weight: load)
                return rec
            }

            guard let next = Self.nextLoad(after: load, measurement: m, config: config) else {
                rec.action = .maintain
                rec.reason = .topOfRangeNoHeavierLoad
                setAmounts(Array(repeating: top, count: sets))
                rec.reasonText = text.noHeavierLoad(weight: load)
                rec.notes.append(text.noHeavierLoadNote)
                return rec
            }

            rec.action = .increaseWeight
            rec.reason = .topOfRangeReached
            rec.targetWeight = next
            setAmounts(Array(repeating: bottom, count: sets))
            if m == .bodyweightReps, LoadMath.key(load) >= 0 {
                rec.notes.append(text.bodyweightLoadNote)
            }
            if effort.isConfirmed {
                rec.confidence = .high
                rec.reasonText = text.increaseHigh(next: next)
            } else {
                rec.confidence = .conditional
                rec.reasonText = text.increaseConditional(next: next)
                rec.conditions = text.increaseConditions
            }
            return rec
        }

        // Below the top of the range.
        let previous = comparable.dropFirst().first
        let belowMin = amounts.contains { $0 < bottom }

        // Rule 7b — sets below the minimum in 2 consecutive comparable sessions at the same load.
        if belowMin, let previous,
           let previousLoad = HistoryAnalyzer.workingLoad(of: previous),
           LoadMath.isEqual(previousLoad, load),
           HistoryAnalyzer.evaluatedSets(of: previous, limit: sets).contains(where: { $0.amount(for: m) < bottom }) {
            rec.action = .reassess
            rec.reason = .repeatedBelowRepMin
            setAmounts(Array(repeating: bottom, count: sets))
            rec.reasonText = text.repeatedBelowMin()
            return rec
        }

        // Rule 7 — lower performance than the previous comparable session: keep the load, show history.
        // Evaluated before rule 6 so that a drop is never answered with "add reps" (case 2.D-4).
        if let previous, let drop = Self.performanceDrop(last: last, previous: previous, sets: sets, measurement: m, oneRepMax: input.oneRepMax) {
            rec.action = .maintain
            rec.reason = .performanceDropped
            let previousAmounts = HistoryAnalyzer.evaluatedSets(of: previous, limit: sets)
                .map { min(max($0.amount(for: m), bottom), top) }
            setAmounts(previousAmounts + Array(repeating: bottom, count: max(0, sets - previousAmounts.count)))
            switch drop {
            case let .sameLoad(lastTotal, previousTotal):
                rec.reasonText = text.performanceDroppedSameLoad(lastTotal: lastTotal, previousTotal: previousTotal, weight: load)
            case .estimate:
                rec.reasonText = text.performanceDroppedEstimate(weight: load)
            }
            return rec
        }

        if belowMin {
            rec.action = .maintain
            rec.reason = .belowRepMin
            setAmounts(amounts.map { min(max($0, bottom), top) })
            rec.reasonText = text.belowMin(weight: load)
            return rec
        }

        // Rule 6 — inside the range: same load, +1 rep (or +step seconds) on sets below the top,
        // only if compatible with the target effort.
        if effort == .belowTarget {
            rec.action = .maintain
            rec.reason = .repsHeldByEffort
            setAmounts(amounts)
            rec.reasonText = text.repsHeldByEffort(weight: load)
            return rec
        }

        rec.action = .increaseReps
        rec.reason = .belowTopOfRange
        setAmounts(amounts.map { $0 < top ? min($0 + step, top) : $0 })
        rec.reasonText = text.belowTop(weight: load)
        if effort.isConfirmed {
            rec.confidence = .high
        } else {
            rec.confidence = .conditional
            rec.conditions = text.belowTopConditions
        }
        return rec
    }

    // MARK: - Helpers

    static func assessEffort(_ sets: [PerformedSet], targetRIR: Int?) -> Effort {
        let values = sets.map(\.effectiveRIR)
        if let target = targetRIR, values.contains(where: { ($0 ?? .infinity) < Double(target) }) {
            return .belowTarget
        }
        guard values.allSatisfy({ $0 != nil }) else { return .unknown }
        return targetRIR == nil ? .recordedNoTarget : .meetsTarget
    }

    /// Calendar days between two instants, in the user's calendar.
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Consecutive comparable sessions (newest first) at `load` with all target sets at the top.
    static func topStreak(_ comparable: [ExercisePerformance], load: Double, sets: Int, top: Int, measurement: MeasurementType) -> Int {
        var streak = 0
        for performance in comparable {
            guard let l = HistoryAnalyzer.workingLoad(of: performance), LoadMath.isEqual(l, load) else { break }
            let evaluated = HistoryAnalyzer.evaluatedSets(of: performance, limit: sets)
            guard evaluated.count >= sets, evaluated.allSatisfy({ $0.amount(for: measurement) >= top }) else { break }
            streak += 1
        }
        return streak
    }

    /// Next real load. Body-weight work with assistance reduces the assistance first.
    static func nextLoad(after load: Double, measurement: MeasurementType, config: ProgressionConfig) -> Double? {
        if measurement == .bodyweightReps, LoadMath.key(load) < 0 {
            return LoadMath.normalized(min(0, load + config.increment))
        }
        return LoadMath.nextLoad(after: load, increment: config.increment, availableWeights: config.availableWeights)
    }

    enum Drop {
        case sameLoad(lastTotal: Int, previousTotal: Int)
        case estimate
    }

    /// Lower performance than the previous comparable session:
    /// - same load: fewer total reps over the sets both sessions share;
    /// - lower load (weightReps only): lower best e1RM (uncapped formula, comparison only);
    /// - higher load: never a drop (fewer reps after a load increase is expected).
    static func performanceDrop(last: ExercisePerformance, previous: ExercisePerformance, sets: Int, measurement: MeasurementType, oneRepMax: OneRepMaxSettings) -> Drop? {
        guard let lastLoad = HistoryAnalyzer.workingLoad(of: last),
              let previousLoad = HistoryAnalyzer.workingLoad(of: previous) else { return nil }
        let lastSets = HistoryAnalyzer.evaluatedSets(of: last, limit: sets)
        let previousSets = HistoryAnalyzer.evaluatedSets(of: previous, limit: sets)

        if LoadMath.isEqual(lastLoad, previousLoad) {
            let k = min(lastSets.count, previousSets.count)
            guard k > 0 else { return nil }
            let lastTotal = lastSets.prefix(k).reduce(0) { $0 + $1.amount(for: measurement) }
            let previousTotal = previousSets.prefix(k).reduce(0) { $0 + $1.amount(for: measurement) }
            return lastTotal < previousTotal ? .sameLoad(lastTotal: lastTotal, previousTotal: previousTotal) : nil
        }

        guard measurement == .weightReps, LoadMath.key(lastLoad) < LoadMath.key(previousLoad) else { return nil }
        func best(_ sets: [PerformedSet]) -> Double? {
            sets.compactMap { s in
                s.weight.flatMap { w in s.reps.flatMap { OneRepMax.raw(weight: w, reps: $0, formula: oneRepMax.formula) } }
            }.max()
        }
        guard let lastBest = best(lastSets), let previousBest = best(previousSets) else { return nil }
        return LoadMath.key(lastBest) < LoadMath.key(previousBest) ? .estimate : nil
    }

    private func appendTrendNotes(_ rec: inout Recommendation, text: RecommendationText) {
        switch rec.trend {
        case .possiblePlateau: rec.notes.append(text.plateauNote)
        case .declining: rec.notes.append(text.decliningNote)
        case .insufficientData, .progressing, .stable: break
        }
    }
}
