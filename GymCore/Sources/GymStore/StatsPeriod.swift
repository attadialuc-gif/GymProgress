import Foundation
import GymCore

/// Period filters of the Progress screen (section 9.4).
public enum StatsPeriod: Hashable, Sendable {
    case week
    case last30Days
    case calendarMonth
    case last90Days
    case calendarYear
    case last12Months
    case custom(DateInterval)

    public var label: String {
        switch self {
        case .week: "Semana"
        case .last30Days: "Últimos 30 días"
        case .calendarMonth: "Mes"
        case .last90Days: "Últimos 90 días"
        case .calendarYear: "Año"
        case .last12Months: "Últimos 12 meses"
        case .custom: "Personalizado"
        }
    }

    /// Calendar periods (week, month, year) are still running until they end.
    public var isCalendarPeriod: Bool {
        switch self {
        case .week, .calendarMonth, .calendarYear: true
        case .last30Days, .last90Days, .last12Months, .custom: false
        }
    }

    /// Half-open interval [start, end) in the user's calendar.
    public func interval(now: Date, calendar: TrainingCalendar) -> DateInterval {
        let cal = calendar.calendar
        let tomorrow = calendar.addDays(1, to: calendar.day(of: now))
        switch self {
        case .week:
            let start = calendar.weekStart(of: now)
            return DateInterval(start: start, end: calendar.addDays(7, to: start))
        case .last30Days:
            return DateInterval(start: calendar.addDays(-30, to: tomorrow), end: tomorrow)
        case .last90Days:
            return DateInterval(start: calendar.addDays(-90, to: tomorrow), end: tomorrow)
        case .calendarMonth:
            let start = calendar.startOfMonth(now)
            return DateInterval(start: start, end: cal.date(byAdding: .month, value: 1, to: start)!)
        case .calendarYear:
            let start = cal.date(from: cal.dateComponents([.year], from: now))!
            return DateInterval(start: start, end: cal.date(byAdding: .year, value: 1, to: start)!)
        case .last12Months:
            return DateInterval(start: cal.date(byAdding: .month, value: -12, to: tomorrow)!, end: tomorrow)
        case let .custom(interval):
            return DateInterval(start: calendar.day(of: interval.start), end: calendar.addDays(1, to: calendar.day(of: interval.end)))
        }
    }

    /// The equivalent previous period (previous week, previous month, same length before…).
    public func previousInterval(now: Date, calendar: TrainingCalendar) -> DateInterval {
        let current = interval(now: now, calendar: calendar)
        let cal = calendar.calendar
        switch self {
        case .week:
            return DateInterval(start: calendar.addDays(-7, to: current.start), end: current.start)
        case .calendarMonth:
            return DateInterval(start: cal.date(byAdding: .month, value: -1, to: current.start)!, end: current.start)
        case .calendarYear:
            return DateInterval(start: cal.date(byAdding: .year, value: -1, to: current.start)!, end: current.start)
        case .last12Months:
            return DateInterval(start: cal.date(byAdding: .month, value: -12, to: current.start)!, end: current.start)
        case .last30Days, .last90Days, .custom:
            let days = calendar.daysBetween(current.start, current.end)
            return DateInterval(start: calendar.addDays(-days, to: current.start), end: current.start)
        }
    }

    /// A fair comparison: for a calendar period that is still running, both sides cover the same
    /// number of elapsed days (this week through today vs. the previous week's same days), so a
    /// partial period is never compared with a complete one.
    public func comparableIntervals(now: Date, calendar: TrainingCalendar) -> (current: DateInterval, previous: DateInterval) {
        let current = interval(now: now, calendar: calendar)
        let previous = previousInterval(now: now, calendar: calendar)
        guard isCalendarPeriod else { return (current, previous) }
        let tomorrow = calendar.addDays(1, to: calendar.day(of: now))
        guard tomorrow < current.end else { return (current, previous) }
        let elapsed = calendar.daysBetween(current.start, tomorrow)
        let previousEnd = min(calendar.addDays(elapsed, to: previous.start), previous.end)
        return (DateInterval(start: current.start, end: tomorrow), DateInterval(start: previous.start, end: previousEnd))
    }
}
