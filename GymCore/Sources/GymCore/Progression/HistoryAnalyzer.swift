import Foundation

/// Filters, merges and orders history deterministically. Shared by strategies and metrics.
public enum HistoryAnalyzer {

    /// Comparable performances for `input`, newest first (section 8.1):
    /// completed session, not atypical, not the current session, not in the future, same
    /// measurement, equivalent context (equal or linked), at least one valid progression set.
    /// Several logs of the same exercise in one session are merged into one performance.
    public static func comparable(_ input: ProgressionInput) -> [ExercisePerformance] {
        let equivalent = ComparabilityResolver(links: input.links).equivalenceClass(of: input.context)
        return eligible(input).filter { equivalent.contains($0.context.normalized) }
    }

    /// Most recent eligible performance of the same exercise in a context that is *not*
    /// equivalent. Shown only as a "no equivalente" reference.
    public static func nonEquivalentReference(_ input: ProgressionInput) -> ExercisePerformance? {
        let equivalent = ComparabilityResolver(links: input.links).equivalenceClass(of: input.context)
        return eligible(input).first {
            $0.context.exerciseId == input.context.exerciseId && !equivalent.contains($0.context.normalized)
        }
    }

    private static func eligible(_ input: ProgressionInput) -> [ExercisePerformance] {
        let filtered = input.history.filter { perf in
            perf.sessionStatus == .completed
                && !perf.isAtypical
                && perf.sessionId != input.excludingSessionId
                && perf.sessionStart <= input.now
                && perf.measurement == input.measurement
        }
        return merged(filtered)
            .filter { !$0.progressionSets.isEmpty }
            .sorted(by: newestFirst)
    }

    /// Merges logs that share session and context; sets keep a deterministic order.
    static func merged(_ performances: [ExercisePerformance]) -> [ExercisePerformance] {
        struct Key: Hashable { let session: UUID; let context: ComparabilityContext }
        let groups = Dictionary(grouping: performances) { Key(session: $0.sessionId, context: $0.context.normalized) }
        return groups.values.map { group -> ExercisePerformance in
            let ordered = group.sorted { $0.exerciseLogId.uuidString < $1.exerciseLogId.uuidString }
            var base = ordered[0]
            let sets = ordered.flatMap { perf in perf.sets.sorted(by: setOrder) }
            base.sets = sets.enumerated().map { i, s in var copy = s; copy.index = i; return copy }
            return base
        }
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
        if a.weight != b.weight { return (a.weight ?? -1) < (b.weight ?? -1) }
        return (a.reps ?? -1) < (b.reps ?? -1)
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
