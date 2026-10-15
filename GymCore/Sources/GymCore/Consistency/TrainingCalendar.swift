import Foundation

/// The user's calendar for "training day" and "week" computations (section 8.6).
/// Instants are stored as `Date` (UTC); days and weeks are always derived with this calendar, in the
/// user's time zone. A session belongs to the day on which it *started* (even if it crosses midnight).
public struct TrainingCalendar: Sendable {
    public private(set) var calendar: Calendar

    /// - Parameters:
    ///   - firstWeekday: 1 = Sunday … 7 = Saturday (Foundation convention). Default Monday (2).
    public init(timeZone: TimeZone, firstWeekday: Int = 2, locale: Locale = GymFormat.defaultLocale) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = locale
        cal.firstWeekday = min(max(firstWeekday, 1), 7)
        cal.minimumDaysInFirstWeek = 4
        self.calendar = cal
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 1 = Sunday … 7 = Saturday.
    public func weekday(of date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Start of the week containing `date`, honoring `firstWeekday`.
    public func weekStart(of date: Date) -> Date {
        let day = self.day(of: date)
        let offset = (weekday(of: day) - calendar.firstWeekday + 7) % 7
        return addDays(-offset, to: day)
    }

    /// Adds calendar days (DST-safe: a "day" may last 23 or 25 hours).
    public func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// Whole calendar days from `a` to `b` (can be negative).
    public func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: day(of: a), to: day(of: b)).day ?? 0
    }

    /// The 7 day starts of the week containing `date`.
    public func daysOfWeek(containing date: Date) -> [Date] {
        let start = weekStart(of: date)
        return (0..<7).map { addDays($0, to: start) }
    }

    public func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    public func daysInMonth(containing date: Date) -> [Date] {
        let start = startOfMonth(date)
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        return (0..<count).map { addDays($0, to: start) }
    }
}
