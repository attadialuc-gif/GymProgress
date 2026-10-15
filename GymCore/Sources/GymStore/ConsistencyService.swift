import Foundation
import GymCore

/// One calendar day for the monthly / weekly views.
public struct CalendarDay: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable {
        /// At least one valid (completed) session that day.
        case completed
        /// Planned, in the future or today without a session yet.
        case planned
        /// Planned, in the past, and no valid session that day.
        case missed
        /// Not planned (scheduled rest or no plan) and no session.
        case rest
    }

    public var id: Date { date }
    public var date: Date
    public var status: Status
    public var plannedRoutineId: UUID?
    public var plannedRoutineName: String?
    public var sessionIds: [UUID]
    public var isToday: Bool
}

public struct WeekSummary: Sendable, Hashable {
    public var weekStart: Date
    public var planned: Int
    public var validSessions: Int
    public var weeklyGoal: Int
    /// min(1, valid / goal): the UI celebrates 100 % without pushing to train more.
    public var goalFraction: Double
    public var goalMet: Bool
}

public struct StreakSummary: Sendable, Hashable {
    public var result: StreakResult
    /// User-facing definition of the mode in use (section 8.5: show the mode and its definition).
    public var definition: String
}

/// Calendar, schedule and consistency (section 8.5). Built on the pure functions of GymCore.
@MainActor
public struct ConsistencyService {
    public let repository: any GymRepository
    public var timeZone: TimeZone

    public init(repository: any GymRepository, timeZone: TimeZone = .current) {
        self.repository = repository
        self.timeZone = timeZone
    }

    public var calendar: TrainingCalendar {
        TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday)
    }

    private var minSets: Int { repository.settings().minSetsForValidSession }

    // MARK: Schedule

    /// Replaces the weekly plan from `from` onwards (append-only: past days keep their plan).
    /// `assignments`: weekday (1 = Sunday … 7 = Saturday) → routine. Missing weekdays = rest.
    public func setWeeklyPlan(_ assignments: [Int: UUID], from: Date, now: Date) throws {
        // Never earlier than today: a plan change can't rewrite planned/missed days in the past.
        let start = max(calendar.day(of: from), calendar.day(of: now))
        for entry in Schedule.weeklyPlanEntries(assignments: assignments, validFrom: start, createdAt: now, calendar: calendar) {
            try repository.insertScheduleEntry(entry)
        }
    }

    /// Plan in force on `day` (weekday → routine).
    public func plan(asOf day: Date) -> [Int: UUID] {
        Schedule.currentAssignments(asOf: day, entries: repository.scheduleEntries(), calendar: calendar)
    }

    public func plannedRoutine(on day: Date) -> UUID? {
        Schedule.plannedRoutine(on: day, entries: repository.scheduleEntries(), calendar: calendar)
    }

    /// Next planned workout from today: skips today when today's planned routine was already
    /// done (or today is a rest day). Looks up to two weeks ahead; `nil` without a plan.
    public func nextPlannedWorkout(now: Date) -> (date: Date, routineId: UUID)? {
        let entries = repository.scheduleEntries()
        guard !entries.isEmpty else { return nil }
        let today = calendar.day(of: now)
        let doneToday = repository.sessions().contains {
            $0.status == .completed && calendar.day(of: $0.startedAt) == today
        }
        for offset in 0..<14 {
            let day = calendar.addDays(offset, to: today)
            if offset == 0 && doneToday { continue }
            if let routine = Schedule.plannedRoutine(on: day, entries: entries, calendar: calendar) {
                return (day, routine)
            }
        }
        return nil
    }

    // MARK: Calendar

    public func month(containing date: Date, now: Date) -> [CalendarDay] {
        days(calendar.daysInMonth(containing: date), now: now)
    }

    public func week(containing date: Date, now: Date) -> [CalendarDay] {
        days(calendar.daysOfWeek(containing: date), now: now)
    }

    private func days(_ dayStarts: [Date], now: Date) -> [CalendarDay] {
        let cal = calendar
        let entries = repository.scheduleEntries()
        let digests = HistoryService(repository: repository).sessionDigests()
        let routineNames = Dictionary(repository.routines().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var validByDay: [Date: [UUID]] = [:]
        for d in digests where d.isValid(minSets: minSets) {
            validByDay[cal.day(of: d.start), default: []].append(d.id)
        }
        let today = cal.day(of: now)
        return dayStarts.map { day in
            let planned = Schedule.plannedRoutine(on: day, entries: entries, calendar: cal)
            let sessions = validByDay[day] ?? []
            let status: CalendarDay.Status
            if !sessions.isEmpty {
                status = .completed
            } else if planned != nil {
                status = day < today ? .missed : .planned
            } else {
                status = .rest
            }
            return CalendarDay(
                date: day,
                status: status,
                plannedRoutineId: planned,
                plannedRoutineName: planned.flatMap { routineNames[$0] },
                sessionIds: sessions,
                isToday: day == today
            )
        }
    }

    // MARK: Consistency

    public func weekSummary(now: Date) -> WeekSummary {
        let settings = repository.settings()
        let digests = HistoryService(repository: repository).sessionDigests()
        let progress = Streaks.weeklyGoalProgress(sessions: digests, goal: settings.weeklyGoal, minSets: minSets, now: now, calendar: calendar)
        let planned = Schedule.plannedDays(inWeekOf: now, entries: repository.scheduleEntries(), calendar: calendar).count
        return WeekSummary(
            weekStart: calendar.weekStart(of: now),
            planned: planned,
            validSessions: progress.done,
            weeklyGoal: progress.goal,
            goalFraction: progress.fraction,
            goalMet: progress.done >= progress.goal
        )
    }

    public func streak(now: Date) -> StreakSummary {
        let settings = repository.settings()
        let digests = HistoryService(repository: repository).sessionDigests()
        switch settings.streakMode {
        case .weeklyPlan:
            let weeks = Streaks.weeklyCompliance(sessions: digests, schedule: repository.scheduleEntries(), minSets: minSets, now: now, calendar: calendar)
            return StreakSummary(
                result: Streaks.weeklyStreak(weeks),
                definition: "Semanas seguidas cumpliendo el plan: entrenamientos válidos (≥ \(minSets) series efectivas) ≥ días planificados. Los descansos programados no cuentan como fallo y la semana en curso no corta la racha." + (repository.scheduleEntries().isEmpty ? " Necesita un plan semanal: definilo en Calendario o cambiá el modo de racha en Perfil." : "")
            )
        case .dayGap:
            let days = Streaks.trainingDays(digests, minSets: minSets, calendar: calendar)
            return StreakSummary(
                result: Streaks.dayGapStreak(trainingDays: days, maxGapDays: settings.maxGapDays, now: now, calendar: calendar),
                definition: "Días de entrenamiento seguidos, con no más de \(settings.maxGapDays) días entre un entrenamiento válido (≥ \(minSets) series efectivas) y el siguiente."
            )
        }
    }
}
