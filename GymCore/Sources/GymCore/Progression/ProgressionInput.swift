import Foundation

/// Everything the engine needs. The engine reads nothing else: no clock, no database, no globals.
public struct ProgressionInput: Sendable {
    /// Context of the exercise being opened (exercise, variant, machine, load mode).
    public var context: ComparabilityContext
    public var measurement: MeasurementType
    /// Effective config (routine override ?? exercise config). Sanitized by the engine.
    public var config: ProgressionConfig
    /// Any history; the engine filters what is comparable and sorts it itself.
    public var history: [ExercisePerformance]
    /// User-created equivalences between contexts.
    public var links: [ComparabilityLink]
    /// Injected "now".
    public var now: Date
    /// Session currently in progress: excluded so today's sets never alter today's target.
    public var excludingSessionId: UUID?
    /// User calendar (time zone) for day counting.
    public var calendar: Calendar
    /// Locale for the explanation text.
    public var locale: Locale
    public var oneRepMax: OneRepMaxSettings
    public var trendThresholds: TrendThresholds

    public init(
        context: ComparabilityContext,
        measurement: MeasurementType,
        config: ProgressionConfig,
        history: [ExercisePerformance],
        links: [ComparabilityLink] = [],
        now: Date,
        excludingSessionId: UUID? = nil,
        calendar: Calendar,
        locale: Locale = GymFormat.defaultLocale,
        oneRepMax: OneRepMaxSettings = .default,
        trendThresholds: TrendThresholds = .default
    ) {
        self.context = context
        self.measurement = measurement
        self.config = config
        self.history = history
        self.links = links
        self.now = now
        self.excludingSessionId = excludingSessionId
        self.calendar = calendar
        self.locale = locale
        self.oneRepMax = oneRepMax
        self.trendThresholds = trendThresholds
    }
}

/// A progression strategy turns comparable history into a recommendation. Implementations must be
/// pure and deterministic. Adding a strategy never requires UI changes.
public protocol ProgressionStrategy: Sendable {
    var kind: ProgressionStrategyKind { get }
    func recommend(_ input: ProgressionInput) -> Recommendation
}

public enum ProgressionEngine {
    public static func strategy(for kind: ProgressionStrategyKind) -> any ProgressionStrategy {
        switch kind {
        case .doubleProgression: DoubleProgressionStrategy()
        }
    }

    /// Entry point used by the app. Deterministic: same input → same output.
    public static func recommend(_ input: ProgressionInput) -> Recommendation {
        strategy(for: input.config.strategy).recommend(input)
    }
}
