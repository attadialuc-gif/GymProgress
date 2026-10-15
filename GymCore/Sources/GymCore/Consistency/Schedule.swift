import Foundation

/// One weekday assignment, valid from a given day. The schedule is append-only: changing it adds new
/// entries with a later `validFrom`; past entries are never rewritten, so planned/missed days in the
/// past are reconstructed exactly. `routineId == nil` declares an explicit rest day.
public struct ScheduleEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// 1 = Sunday … 7 = Saturday.
    public var weekday: Int
    public var routineId: UUID?
    /// Start of the first day this entry applies (in the user's calendar).
    public var validFrom: Date
    /// Optional end (exclusive).
    public var validTo: Date?
    public var createdAt: Date

    public init(id: UUID = UUID(), weekday: Int, routineId: UUID?, validFrom: Date, validTo: Date? = nil, createdAt: Date) {
        self.id = id
        self.weekday = weekday
        self.routineId = routineId
        self.validFrom = validFrom
        self.validTo = validTo
        self.createdAt = createdAt
    }
}

public enum Schedule {
    /// Routine planned for `day`, or `nil` when it is a rest / unplanned day.
    /// Among entries for that weekday valid on that day, the latest `validFrom` wins
    /// (ties: later `createdAt`, then id).
    public static func plannedRoutine(on day: Date, entries: [ScheduleEntry], calendar: TrainingCalendar) -> UUID? {
        let dayStart = calendar.day(of: day)
        let weekday = calendar.weekday(of: dayStart)
        let candidates = entries.filter { entry in
            entry.weekday == weekday
                && calendar.day(of: entry.validFrom) <= dayStart
                && (entry.validTo.map { dayStart < calendar.day(of: $0) } ?? true)
        }
        let winner = candidates.max { a, b in
            if a.validFrom != b.validFrom { return a.validFrom < b.validFrom }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
        return winner?.routineId
    }

    public static func isPlanned(_ day: Date, entries: [ScheduleEntry], calendar: TrainingCalendar) -> Bool {
        plannedRoutine(on: day, entries: entries, calendar: calendar) != nil
    }

    /// Planned training days in the week containing `date`.
    public static func plannedDays(inWeekOf date: Date, entries: [ScheduleEntry], calendar: TrainingCalendar) -> [Date] {
        calendar.daysOfWeek(containing: date).filter { isPlanned($0, entries: entries, calendar: calendar) }
    }

    /// Entries that set the whole week plan from `validFrom`: one entry per weekday (1…7), with
    /// `nil` for rest days, so removing a day from the plan is explicit and the past is untouched.
    public static func weeklyPlanEntries(assignments: [Int: UUID], validFrom: Date, createdAt: Date, calendar: TrainingCalendar, makeId: () -> UUID = UUID.init) -> [ScheduleEntry] {
        let start = calendar.day(of: validFrom)
        return (1...7).map { weekday in
            ScheduleEntry(id: makeId(), weekday: weekday, routineId: assignments[weekday], validFrom: start, createdAt: createdAt)
        }
    }

    /// Current assignment per weekday (for editing): the entries that apply on `day` and after.
    public static func currentAssignments(asOf day: Date, entries: [ScheduleEntry], calendar: TrainingCalendar) -> [Int: UUID] {
        var result: [Int: UUID] = [:]
        for offset in 0..<7 {
            let d = calendar.addDays(offset, to: calendar.day(of: day))
            if let routine = plannedRoutine(on: d, entries: entries, calendar: calendar) {
                result[calendar.weekday(of: d)] = routine
            }
        }
        return result
    }
}
