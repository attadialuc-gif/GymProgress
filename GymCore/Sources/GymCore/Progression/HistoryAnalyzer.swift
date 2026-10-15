import Foundation

/// Filters, merges and orders history deterministically. Shared by strategies and metrics.
public enum HistoryAnalyzer {

    /// Comparable performances for `input`, newest first (section 8.1):
    /// completed session, not atypical, not the current session, not in the future, same
    /// measurement, equivalent context (equal or linked), at least one valid progression set.
    /// Several logs of the same exercise in one session are merged into one performance.
    public static func comparable(_ input: ProgressionInput) -> [ExercisePerformance] {
        let equivalent = ComparabilityResolver(links: input.links).equivalenceClass(of: input.context)
        // Filter to the equivalence class first, then merge by session: two linked machines used in
        // the same session are ONE comparable session, never two.
        let inClass = eligible(input).filter { equivalent.contains($0.context.normalized) }
        return merged(inClass, bySessionOnly: true)
            .filter { !$0.progressionSets.isEmpty }
            .sorted(by: newestFirst)
    }

    /// Most recent eligible performance of the same exercise in a context that is *not*
    /// equivalent. Shown only as a "no equivalente" reference.
    public static func nonEquivalentReference(_ input: ProgressionInput) -> ExercisePerformance? {
        let equivalent = ComparabilityResolver(links: input.links).equivalenceClass(of: input.context)
        let others = eligible(input).filter {
            $0.context.exerciseId == input.context.exerciseId && !equivalent.contains($0.context.normalized)
        }
        return merged(others, bySessionOnly: false)
            .filter { !$0.progressionSets.isEmpty }
            .sorted(by: newestFirst)
            .first
    }

    private static func eligible(_ input: ProgressionInput) -> [ExercisePerformance] {
        input.history.filter { perf in
            perf.sessionStatus == .completed
                && !perf.isAtypical
                && perf.sessionId != input.excludingSessionId
                && perf.sessionStart <= input.now
                && perf.measurement == input.measurement
        }
    }

    /// Merges logs of the same session (and, unless `bySessionOnly`, the same context). Logs are
    /// concatenated in execution order (first completed set), sets inside a log by index.
    static func merged(_ performances: [ExercisePerformance], bySessionOnly: Bool) -> [ExercisePerformance] {
        struct Key: Hashable { let session: UUID; let context: ComparabilityContext? }
        let groups = Dictionary(grouping: performances) {
            Key(session: $0.sessionId, context: bySessionOnly ? nil : $0.context.normalized)
        }
        return groups.values.map { group -> ExercisePerformance in
            let ordered = group.sorted { a, b in
                let fa = firstCompletion(a), fb = firstCompletion(b)
                if fa != fb { return fa < fb }
                if a.context.sortKey != b.context.sortKey { return a.context.sortKey < b.context.sortKey }
                return a.exerciseLogId.uuidString < b.exerciseLogId.uuidString
            }
            var base = ordered[0]
            let sets = ordered.flatMap { perf in perf.sets.sorted(by: setOrder) }
            base.sets = sets.enumerated().map { i, s in var copy = s; copy.index = i; return copy }
            return base
        }
    }

    private static func firstCompletion(_ p: ExercisePerformance) -> Date {
        p.sets.compactMap(\.completedAt).min() ?? .distantFuture
    }

    static func newestFirst(_ a: ExercisePerformance, _ b: ExercisePerformance) -> Bool {
        if a.sessionStart != b.sessionStart { return a.sessionStart > b.sessionStart }
        if a.sessionId != b.sessionId { return a.sessionId.uuidString > b.sessionId.uuidString }
        if a.context.sortKey != b.context.sortKey { return a.context.sortKey < b.context.sortKey }
        return a.exerciseLogId.uuidString < b.exerciseLogId.uuidString
    }

    static func setOrder(_ a: PerformedSet, _ b: PerformedSet) -> Bool {
        if a.index != b.index { return a.index < b.index }
        let ac = a.completedAt ?? .distantFuture
        let bc = b.completedAt ?? .distantFuture
        if ac != bc { return ac < bc }
        // Total order: identical-looking sets with different effort must not depend on input order.
        let ka = (a.kind.rawValue, a.status.rawValue, a.weight ?? -1, a.reps ?? -1, a.seconds ?? -1)
        let kb = (b.kind.rawValue, b.status.rawValue, b.weight ?? -1, b.reps ?? -1, b.seconds ?? -1)
        if ka != kb { return ka < kb }
        let ea = (a.rir ?? -1, a.rpe ?? -1, a.addedWeight ?? -1, a.assistance ?? -1)
        let eb = (b.rir ?? -1, b.rpe ?? -1, b.addedWeight ?? -1, b.assistance ?? -1)
        if ea != eb { return ea < eb }
        return !a.excludedFromEstimates && b.excludedFromEstimates
    }

    /// Working load: the most frequent load among progression sets; ties → the heavier load.
    public static func workingLoad(of performance: ExercisePerformance) -> Double? {
        let loads = performance.progressionSets.map { LoadMath.key($0.progressionLoad(for: performance.measurement)) }
        guard !loads.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for key in loads { counts[key, default: 0] += 1 }
        let best = counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }!
        return Double(best.key) * LoadMath.resolution
    }

    /// Sets evaluated by double progression: progression sets at the working load, in order,
    /// limited to the first `limit` (extra sets beyond the target are ignored).
    public static func evaluatedSets(of performance: ExercisePerformance, limit: Int) -> [PerformedSet] {
        guard let load = workingLoad(of: performance) else { return [] }
        return Array(
            performance.progressionSets
                .filter { LoadMath.isEqual($0.progressionLoad(for: performance.measurement), load) }
                .prefix(limit)
        )
    }

    public static func summary(of performance: ExercisePerformance) -> PerformanceSummary {
        let measurement = performance.measurement
        return PerformanceSummary(
            sessionId: performance.sessionId,
            exerciseLogId: performance.exerciseLogId,
            date: performance.sessionStart,
            context: performance.context,
            measurement: measurement,
            workingLoad: workingLoad(of: performance) ?? 0,
            sets: performance.progressionSets.map {
                PerformanceSummary.SetSummary(
                    load: LoadMath.normalized($0.progressionLoad(for: measurement)),
                    amount: $0.amount(for: measurement),
                    rir: $0.effectiveRIR
                )
            }
        )
    }
}
