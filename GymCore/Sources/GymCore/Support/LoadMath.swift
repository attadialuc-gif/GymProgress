import Foundation

/// Load arithmetic with a fixed resolution of 1 gram, so floating-point noise (0.1 + 0.2) never
/// changes a comparison or a recommendation.
public enum LoadMath {
    public static let resolution: Double = 0.001

    /// Rounds to the 1 g grid.
    public static func normalized(_ value: Double) -> Double {
        (value / resolution).rounded() * resolution
    }

    /// Integer key in grams; use it for grouping and equality.
    public static func key(_ value: Double) -> Int {
        Int((value / resolution).rounded())
    }

    public static func isEqual(_ a: Double, _ b: Double) -> Bool {
        key(a) == key(b)
    }

    /// Next real load above `current`.
    /// - When `availableWeights` is non-empty, it is the smallest available weight strictly above
    ///   `current` (or `nil` when there is none: the caller must keep the load and warn).
    /// - Otherwise it is `current + increment`.
    public static func nextLoad(after current: Double, increment: Double, availableWeights: [Double]?) -> Double? {
        if let available = availableWeights, !available.isEmpty {
            let currentKey = key(current)
            return available
                .map(normalized)
                .sorted()
                .first { key($0) > currentKey }
        }
        guard increment > 0 else { return nil }
        return normalized(current + increment)
    }
}
