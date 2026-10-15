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
}

/// Aggregates for a period. Every number comes from recorded sets (never invented).
public struct PeriodTotals: Sendable, Hashable {
    public var validSessions: Int
    public var effectiveSets: Int
    /// External load volume in kg (section 8.1). Not a proxy for strength or hypertrophy.
    public var volume: Double
    public var trainingDays: Int
}

public struct PeriodComparison: Sendable, Hashable {
    public var current: PeriodTotals
    public var previous: PeriodTotals
}

/// One session of one exercise, as a chart point.
public struct ExercisePoint: Sendable, Hashable, Identifiable {
    public var id: UUID { exerciseLogId }
    public var exerciseLogId: UUID
    public var date: Date
    public var workingLoad: Double
    public var totalReps: Int
    public var bestSetReps: Int
    /// Estimated, capped by the user's rep limit; nil when no set qualifies.
    public var estimatedOneRepMax: Double?
    public var volume: Double
    public var effectiveSets: Int
    public var isAtypical: Bool
    public var contextLabel: String?
}

public struct RecentRecord: Sendable, Hashable, Identifiable {
    public var id: String { "\(exerciseId.uuidString)-\(record.kind.rawValue)-\(record.date.timeIntervalSince1970)" }
    public var exerciseId: UUID
    public var exerciseName: String
    public var record: PersonalRecord
}

public struct GoalProgress: Sendable, Hashable, Identifiable {
    public var id: UUID { goal.id }
    public var goal: Goal
    /// Best value achieved so far for the goal's metric (nil = no data yet).
    public var current: Double?
    public var fraction: Double
    public var achieved: Bool
}

/// Statistics for Progress, Home and Records (sections 8.3–8.4, 9.4, 9.6).
@MainActor
public struct StatsService {
    public let repository: any GymRepository
    public var timeZone: TimeZone

    public init(repository: any GymRepository, timeZone: TimeZone = .current) {
        self.repository = repository
        self.timeZone = timeZone
    }

    public var calendar: TrainingCalendar {
        TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday)
    }

    private var history: HistoryService { HistoryService(repository: repository) }

    // MARK: Totals and comparisons

    public func totals(in interval: DateInterval, routineId: UUID? = nil) -> PeriodTotals {
        let settings = repository.settings()
        let sessions = repository.sessions().filter {
            $0.status == .completed && interval.containsHalfOpen($0.startedAt)
                && (routineId == nil || $0.routineId == routineId)
        }
        var effective = 0
        var volume = 0.0
        var valid = 0
        var days = Set<Date>()
        for session in sessions {
            var sessionSets = 0
            for log in repository.exerciseLogs(sessionId: session.id) {
                let v = Volume.of(history.performance(of: log, in: session), bodyweight: settings.bodyweightKg)
                sessionSets += v.effectiveSets
                volume += v.total
            }
            effective += sessionSets
            if sessionSets >= settings.minSetsForValidSession {
                valid += 1
                days.insert(calendar.day(of: session.startedAt))
            }
        }
        return PeriodTotals(validSessions: valid, effectiveSets: effective, volume: LoadMath.normalized(volume), trainingDays: days.count)
    }

    public func comparison(_ period: StatsPeriod, now: Date, routineId: UUID? = nil) -> PeriodComparison {
        PeriodComparison(
            current: totals(in: period.interval(now: now, calendar: calendar), routineId: routineId),
            previous: totals(in: period.previousInterval(now: now, calendar: calendar), routineId: routineId)
        )
    }

    // MARK: Exercise series

    /// One point per completed session of the exercise inside `interval`, oldest first.
    /// Atypical sessions are included but flagged (charts show them; trends exclude them).
    public func exerciseSeries(exerciseId: UUID, in interval: DateInterval? = nil) -> [ExercisePoint] {
        let settings = repository.settings()
        return history.exerciseHistory(exerciseId: exerciseId)
            .filter { interval?.containsHalfOpen($0.session.startedAt) ?? true }
            .reversed()
            .compactMap { entry -> ExercisePoint? in
                let perf = entry.performance
                let progression = perf.progressionSets
                guard !progression.isEmpty else { return nil }
                let summary = HistoryAnalyzer.summary(of: perf)
                let volume = Volume.of(perf, bodyweight: settings.bodyweightKg)
                return ExercisePoint(
                    exerciseLogId: entry.log.id,
                    date: entry.session.startedAt,
                    workingLoad: summary.workingLoad,
                    totalReps: summary.amounts.reduce(0, +),
                    bestSetReps: summary.amounts.max() ?? 0,
                    estimatedOneRepMax: OneRepMax.best(in: perf, settings: settings.oneRepMax).map(LoadMath.normalized),
                    volume: volume.total,
                    effectiveSets: volume.effectiveSets,
                    isAtypical: perf.isAtypical,
                    contextLabel: [entry.log.equipmentLabel, entry.log.variantLabel].compactMap { $0 }.first
                )
            }
    }

    // MARK: Muscles

    /// Direct and indirect sets per muscle in the interval (reported separately).
    public func muscleVolume(in interval: DateInterval) -> [MuscleSetVolume] {
        let settings = repository.settings()
        return MuscleVolume.compute(history.muscleWork(in: interval), indirectFactor: settings.indirectSetFactor, calendar: calendar.calendar)
    }

    /// Weekly direct sets for one muscle over the last `weeks` weeks (oldest first).
    public func weeklyDirectSets(muscle: MuscleGroup, weeks: Int, now: Date) -> [(weekStart: Date, directSets: Int, indirectSets: Double)] {
        let currentStart = calendar.weekStart(of: now)
        return (0..<max(1, weeks)).reversed().map { back in
            let start = calendar.addDays(-7 * back, to: currentStart)
            let interval = DateInterval(start: start, end: calendar.addDays(7, to: start))
            let v = muscleVolume(in: interval).first { $0.muscle == muscle }
            return (start, v?.directSets ?? 0, v?.indirectSets ?? 0)
        }
    }

    // MARK: Records and goals

    public func records(exerciseId: UUID) -> RecordSummary {
        PersonalRecords.compute(
            history.exerciseHistory(exerciseId: exerciseId).map(\.performance),
            oneRepMax: repository.settings().oneRepMax,
            bodyweight: repository.settings().bodyweightKg
        )
    }

    /// Records improved within the last `days` days, newest first (real and estimated, labeled).
    public func recentRecords(days: Int, now: Date, limit: Int = 5) -> [RecentRecord] {
        let since = calendar.addDays(-days, to: calendar.day(of: now))
        var result: [RecentRecord] = []
        for exercise in repository.exercises() where repository.hasHistory(exerciseId: exercise.id) {
            let summary = records(exerciseId: exercise.id)
            // Only the first-ever value is not a "record broken"; skip records set in the first session.
            let firstSession = summary.history.first?.sessionId
            for record in summary.history where record.date >= since && record.date <= now && record.sessionId != firstSession {
                result.append(RecentRecord(exerciseId: exercise.id, exerciseName: exercise.name, record: record))
            }
        }
        return Array(result.sorted { $0.record.date > $1.record.date }.prefix(limit))
    }

    public func goalProgress(now: Date) -> [GoalProgress] {
        repository.goals().map { goal in
            let summary = records(exerciseId: goal.exerciseId)
            let current: Double?
            switch goal.metric {
            case .weight: current = summary.maxWeight?.value
            case .estimatedOneRepMax: current = summary.bestEstimatedOneRepMax?.value
            case .sessionVolume: current = summary.maxSessionVolume?.value
            case .repsAtWeight:
                current = goal.weight.flatMap { w in
                    summary.maxRepsAtWeight.filter { ($0.weight ?? 0) >= w - LoadMath.resolution }.map(\.value).max()
                }
            }
            let fraction = current.map { goal.value > 0 ? min(1, $0 / goal.value) : 0 } ?? 0
            return GoalProgress(goal: goal, current: current, fraction: fraction, achieved: (current ?? 0) >= goal.value)
        }
    }

    /// Marks reached goals as achieved (date = now). Returns the newly achieved ones.
    @discardableResult
    public func refreshGoals(now: Date) throws -> [Goal] {
        var achieved: [Goal] = []
        for progress in goalProgress(now: now) where progress.achieved && progress.goal.status == .active {
            var g = progress.goal
            g.status = .achieved
            g.achievedAt = now
            try repository.upsertGoal(g)
            achieved.append(g)
        }
        return achieved
    }
}
