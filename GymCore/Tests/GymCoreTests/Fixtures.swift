import Foundation
@testable import GymCore

/// Deterministic fixtures for progression tests. All dates are UTC; "day n" = 2026-01-05 18:00 UTC + n days.
enum Fx {
    static let benchId = uuid(0xB1)
    static let squatId = uuid(0x51)
    static let pullUpId = uuid(0x9B)
    static let plankId = uuid(0x91)
    static let curlId = uuid(0xC1)

    static let utc = TimeZone(identifier: "UTC")!

    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        cal.firstWeekday = 2
        return cal
    }

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    static let epoch: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 5; c.hour = 18
        return utcCalendar.date(from: c)!
    }()

    static func day(_ n: Int) -> Date {
        epoch.addingTimeInterval(Double(n) * 86_400)
    }

    static let benchContext = ComparabilityContext(exerciseId: benchId, loadMode: .total)

    /// Section 2.D reference config: 3 sets, 8–12 reps, RIR 2, +2.5 kg.
    static let config = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5)

    static func sets(weight: Double, reps: [Int], rir: [Double?]? = nil) -> [PerformedSet] {
        reps.enumerated().map { i, r in
            PerformedSet(index: i, kind: .working, status: .completed, weight: weight, reps: r, rir: rir?[i])
        }
    }

    static func perf(
        _ n: Int,
        day d: Int,
        weight: Double,
        reps: [Int],
        rir: [Double?]? = nil,
        context: ComparabilityContext = benchContext,
        status: SessionStatus = .completed,
        atypical: Bool = false
    ) -> ExercisePerformance {
        ExercisePerformance(
            sessionId: uuid(0x1000 + n),
            exerciseLogId: uuid(0x2000 + n),
            sessionStart: day(d),
            sessionStatus: status,
            isAtypical: atypical,
            context: context,
            measurement: .weightReps,
            sets: sets(weight: weight, reps: reps, rir: rir)
        )
    }

    static func input(
        history: [ExercisePerformance],
        config: ProgressionConfig = config,
        context: ComparabilityContext = benchContext,
        measurement: MeasurementType = .weightReps,
        links: [ComparabilityLink] = [],
        now: Date = day(7),
        excludingSessionId: UUID? = nil
    ) -> ProgressionInput {
        ProgressionInput(
            context: context,
            measurement: measurement,
            config: config,
            history: history,
            links: links,
            now: now,
            excludingSessionId: excludingSessionId,
            calendar: utcCalendar,
            locale: Locale(identifier: "es_AR")
        )
    }
}
