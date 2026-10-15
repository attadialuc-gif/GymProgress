import Foundation

/// Recognized 1RM estimation formulas. Results are always *estimates* and labeled as such.
public enum OneRepMaxFormula: String, Codable, Sendable, CaseIterable, Hashable {
    /// w × (1 + r / 30); r = 1 → w.
    case epley
    /// w × 36 / (37 − r); defined for r < 37.
    case brzycki
}

public struct OneRepMaxSettings: Codable, Sendable, Hashable {
    public var formula: OneRepMaxFormula
    /// Sets with more reps than this are excluded from estimates (default 10).
    public var maxReps: Int

    public init(formula: OneRepMaxFormula = .epley, maxReps: Int = 10) {
        self.formula = formula
        self.maxReps = maxReps
    }

    public static let `default` = OneRepMaxSettings()
}

public enum OneRepMax {
    /// Raw formula value, without the rep cap. `nil` for invalid input.
    public static func raw(weight: Double, reps: Int, formula: OneRepMaxFormula) -> Double? {
        guard weight.isFinite, weight > 0, reps >= 1 else { return nil }
        if reps == 1 { return weight }
        switch formula {
        case .epley:
            return weight * (1 + Double(reps) / 30)
        case .brzycki:
            guard reps < 37 else { return nil }
            return weight * 36 / Double(37 - reps)
        }
    }

    /// Estimate for one set, honoring the rep cap. `nil` when excluded.
    public static func estimate(weight: Double, reps: Int, settings: OneRepMaxSettings = .default) -> Double? {
        guard reps <= settings.maxReps else { return nil }
        return raw(weight: weight, reps: reps, formula: settings.formula)
    }

    /// Best estimate among the effective sets of a performance (weightReps only; sets marked as
    /// excluded by the user are skipped).
    public static func best(in performance: ExercisePerformance, settings: OneRepMaxSettings = .default) -> Double? {
        guard performance.measurement == .weightReps else { return nil }
        return performance.effectiveSets
            .filter { !$0.excludedFromEstimates }
            .compactMap { set -> Double? in
                guard let w = set.weight, let r = set.reps else { return nil }
                return estimate(weight: w, reps: r, settings: settings)
            }
            .max()
    }
}
