import Foundation

/// Minimal session data needed for consistency metrics.
public struct SessionDigest: Codable, Sendable, Hashable {
    public var id: UUID
    public var start: Date
    public var status: SessionStatus
    public var effectiveSets: Int
    public var routineId: UUID?

    public init(id: UUID, start: Date, status: SessionStatus, effectiveSets: Int, routineId: UUID? = nil) {
        self.id = id
        self.start = start
        self.status = status
        self.effectiveSets = effectiveSets
        self.routineId = routineId
    }

    /// Valid session (section 8.5): completed with at least `minSets` effective sets.
    /// Opening the app or an empty session never counts.
    public func isValid(minSets: Int) -> Bool {
        status == .completed && effectiveSets >= max(1, minSets)
    }
}

public enum StreakMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// A: consecutive weeks meeting the plan (valid sessions ≥ planned days that week).
    case weeklyPlan
    /// B: consecutive training days where the gap between valid sessions is at most K days.
    case dayGap
}

public struct WeekCompliance: Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable, Hashable {
        case met
        case missed
        /// No planned days that week: neutral (neither counts nor breaks the streak).
        case noPlan
        /// Current week, not met yet: neutral until the week ends.
        case inProgress
    }

    public var weekStart: Date
    public var planned: Int
    public var valid: Int
    public var status: Status
}

public struct StreakResult: Codable, Sendable, Hashable {
    public var mode: StreakMode
    /// Weeks (mode A) or training days (mode B).
    public var current: Int
    public var best: Int
}

public enum Streaks {

    /// Day starts of valid sessions (one per day), ascending.
    public static func trainingDays(_ sessions: [SessionDigest], minSets: Int, calendar: TrainingCalendar) -> [Date] {
        Array(Set(sessions.filter { $0.isValid(minSets: minSets) }.map { calendar.day(of: $0.start) })).sorted()
    }

    /// Week-by-week compliance from the first relevant week to the week of `now`.
    public static func weeklyCompliance(
        sessions: [SessionDigest],
        schedule: [ScheduleEntry],
        minSets: Int,
        now: Date,
        calendar: TrainingCalendar
    ) -> [WeekCompliance] {
        let valid = sessions.filter { $0.isValid(minSets: minSets) }
        let firstDates = valid.map(\.start) + schedule.map(\.validFrom)
        guard let first = firstDates.min() else { return [] }

        let currentWeek = calendar.weekStart(of: now)
        var week = calendar.weekStart(of: first)
        var result: [WeekCompliance] = []
        var guardCount = 0
        while week <= currentWeek, guardCount < 5_000 {
            guardCount += 1
            let next = calendar.addDays(7, to: week)
            let planned = Schedule.plannedDays(inWeekOf: week, entries: schedule, calendar: calendar).count
            let count = valid.filter { $0.start >= week && $0.start < next }.count
            let status: WeekCompliance.Status
            if planned == 0 {
                status = .noPlan
            } else if count >= planned {
                status = .met
            } else if week == currentWeek {
                status = .inProgress
            } else {
                status = .missed
            }
            result.append(WeekCompliance(weekStart: week, planned: planned, valid: count, status: status))
            week = next
        }
        return result
    }

    /// Mode A: consecutive met weeks. `noPlan` and an unfinished current week are neutral.
    public static func weeklyStreak(_ weeks: [WeekCompliance]) -> StreakResult {
        var best = 0
        var run = 0
        for w in weeks {
            switch w.status {
            case .met:
                run += 1
                best = max(best, run)
            case .missed:
                run = 0
            case .noPlan, .inProgress:
                break
            }
        }
        return StreakResult(mode: .weeklyPlan, current: run, best: best)
    }

    /// Mode B: chains of training days with gaps of at most `maxGapDays` days. The current chain is
    /// alive while `now` is within `maxGapDays` of the last training day.
    public static func dayGapStreak(trainingDays: [Date], maxGapDays: Int, now: Date, calendar: TrainingCalendar) -> StreakResult {
        let k = max(1, maxGapDays)
        var best = 0
        var run = 0
        var previous: Date?
        for day in trainingDays {
            if let p = previous, calendar.daysBetween(p, day) <= k {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        let alive = previous.map { calendar.daysBetween($0, now) <= k } ?? false
        return StreakResult(mode: .dayGap, current: alive ? run : 0, best: best)
    }

    /// Valid sessions this week vs. a weekly goal. Never encourages exceeding it.
    public static func weeklyGoalProgress(sessions: [SessionDigest], goal: Int, minSets: Int, now: Date, calendar: TrainingCalendar) -> (done: Int, goal: Int, fraction: Double) {
        let start = calendar.weekStart(of: now)
        let end = calendar.addDays(7, to: start)
        let done = sessions.filter { $0.isValid(minSets: minSets) && $0.start >= start && $0.start < end }.count
        let g = max(1, goal)
        return (done, g, min(1, Double(done) / Double(g)))
    }
}
