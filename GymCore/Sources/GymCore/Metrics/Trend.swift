import Foundation

/// Documented, configurable thresholds for trend classification (see docs/FORMULAS.md).
public struct TrendThresholds: Codable, Sendable, Hashable {
    /// Minimum comparable sessions before any conclusion (default 3).
    public var minSessions: Int
    /// Only the most recent N sessions are considered (default 6).
    public var window: Int
    /// Least-squares slope / mean, per session, at or above which the trend is "progressing" (+1 %).
    public var progressingSlope: Double
    /// Slope / mean at or below which the trend may be "declining" (−1 %). Also requires a new low.
    public var decliningSlope: Double
    /// (max − min) / mean at or below which a flat series is a "possible plateau" (3 %). Noisier
    /// series are "stable": fluctuation never yields a plateau.
    public var plateauMaxRange: Double

    public init(minSessions: Int = 3, window: Int = 6, progressingSlope: Double = 0.01, decliningSlope: Double = -0.01, plateauMaxRange: Double = 0.03) {
        self.minSessions = minSessions
        self.window = window
        self.progressingSlope = progressingSlope
        self.decliningSlope = decliningSlope
        self.plateauMaxRange = plateauMaxRange
    }

    public static let `default` = TrendThresholds()
}

public enum TrendAnalyzer {
    /// Classifies a chronological series (oldest first).
    public static func classify(_ values: [Double], thresholds: TrendThresholds = .default) -> TrendClassification {
        let minSessions = max(3, thresholds.minSessions)
        guard values.count >= minSessions, values.allSatisfy(\.isFinite) else { return .insufficientData }
        let window = Array(values.suffix(max(minSessions, thresholds.window)))
        let n = Double(window.count)
        let mean = window.reduce(0, +) / n
        guard mean > 0 else { return .insufficientData }

        let xMean = (n - 1) / 2
        var num = 0.0
        var den = 0.0
        for (i, y) in window.enumerated() {
            let dx = Double(i) - xMean
            num += dx * (y - mean)
            den += dx * dx
        }
        let relativeSlope = den > 0 ? (num / den) / mean : 0
        let relativeRange = ((window.max() ?? 0) - (window.min() ?? 0)) / mean

        if relativeSlope >= thresholds.progressingSlope {
            return .progressing
        }
        if relativeSlope <= thresholds.decliningSlope,
           let last = window.last,
           let earlierMin = window.dropLast().min(),
           last < earlierMin {
            return .declining
        }
        if relativeRange <= thresholds.plateauMaxRange {
            return .possiblePlateau
        }
        return .stable
    }

    /// Trend of an exercise from its comparable performances (chronological, oldest first).
    /// Uses the best capped e1RM per session when at least `minSessions` sessions have one;
    /// otherwise total reps (or seconds) over the trailing run of sessions at a constant load.
    public static func classify(
        performances: [ExercisePerformance],
        oneRepMax: OneRepMaxSettings = .default,
        thresholds: TrendThresholds = .default
    ) -> TrendClassification {
        guard performances.count >= max(3, thresholds.minSessions) else { return .insufficientData }

        let e1rms = performances.compactMap { OneRepMax.best(in: $0, settings: oneRepMax) }
        if e1rms.count == performances.count {
            return classify(e1rms, thresholds: thresholds)
        }

        // Constant-load fallback: trailing sessions sharing the same working load.
        let summaries = performances.map { HistoryAnalyzer.summary(of: $0) }
        guard let lastLoad = summaries.last?.workingLoad else { return .insufficientData }
        var run: [Double] = []
        for summary in summaries.reversed() {
            guard LoadMath.isEqual(summary.workingLoad, lastLoad) else { break }
            run.append(Double(summary.amounts.reduce(0, +)))
        }
        return classify(run.reversed(), thresholds: thresholds)
    }
}
