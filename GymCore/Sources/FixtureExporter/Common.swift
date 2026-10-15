import Foundation
import GymCore
import GymStore

// Shared helpers. Same deterministic values as the test fixtures (Fx / SFx in the test targets).

enum FX {
    static let benchId = uuid(0xB1)
    static let squatId = uuid(0x51)
    static let pullUpId = uuid(0x9B)
    static let plankId = uuid(0x91)
    static let curlId = uuid(0xC1)

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        return cal
    }

    /// 2026-01-05 18:00 UTC + n days.
    static let epoch: Date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 18))!

    static func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86_400) }

    static let benchContext = ComparabilityContext(exerciseId: benchId, loadMode: .total)
    static let config = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5)

    static func sets(weight: Double, reps: [Int], rir: [Double?]? = nil) -> [PerformedSet] {
        reps.enumerated().map { i, r in
            PerformedSet(index: i, kind: .working, status: .completed, weight: weight, reps: r, rir: rir?[i])
        }
    }

    static func perf(_ n: Int, day d: Int, weight: Double, reps: [Int], rir: [Double?]? = nil,
                     context: ComparabilityContext = benchContext, status: SessionStatus = .completed,
                     atypical: Bool = false) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: uuid(0x1000 + n), exerciseLogId: uuid(0x2000 + n), sessionStart: day(d),
            sessionStatus: status, isAtypical: atypical, context: context, measurement: .weightReps,
            sets: sets(weight: weight, reps: reps, rir: rir)
        )
    }

    /// Wall-clock date in a time zone.
    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, tz: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let ba = "America/Argentina/Buenos_Aires"
    static let ny = "America/New_York"
}

/// Converts any Encodable value to a JSON object (same encoding as exports: sorted keys,
/// dates as seconds since 1970, nil optionals omitted).
func json<T: Encodable>(_ value: T) -> Any {
    let data = try! GymJSON.encoder.encode(value)
    return try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

/// Optional → JSON value or null.
func nn<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

func jsonOrNull<T: Encodable>(_ value: T?) -> Any {
    value.map { json($0) } ?? NSNull()
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (data + Data("\n".utf8)).write(to: url, options: .atomic)
}

/// Serializable version of `ProgressionInput` (calendar/locale as identifiers).
struct EngineInputDTO: Codable {
    var context: ComparabilityContext
    var measurement: MeasurementType
    var config: ProgressionConfig
    var history: [ExercisePerformance]
    var links: [ComparabilityLink]
    var now: Date
    var excludingSessionId: UUID?
    var timeZone: String
    var firstWeekday: Int
    var locale: String
    var oneRepMax: OneRepMaxSettings
    var trendThresholds: TrendThresholds

    var input: ProgressionInput {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone)!
        cal.firstWeekday = firstWeekday
        return ProgressionInput(
            context: context, measurement: measurement, config: config, history: history, links: links,
            now: now, excludingSessionId: excludingSessionId, calendar: cal, locale: Locale(identifier: locale),
            oneRepMax: oneRepMax, trendThresholds: trendThresholds
        )
    }
}
