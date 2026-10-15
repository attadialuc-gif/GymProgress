import Foundation
import GymCore

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
    /// True when a running calendar period is compared day-for-day with the same elapsed span.
    public var isToDate: Bool
}

/// A group of mutually comparable contexts of one exercise (same machine/variant/load mode, or
/// linked by the user). Records and charts are computed per class (section 8.1).
public struct ContextClass: Sendable, Hashable, Identifiable {
    public var id: String { representative.sortKeyForUI }
    public var representative: ComparabilityContext
    public var contexts: Set<ComparabilityContext>
    /// "estándar" or the machine/variant labels.
    public var label: String
    public var lastUsed: Date
}

/// One session of one exercise, as a chart point.
public struct ExercisePoint: Sendable, Hashable, Identifiable {
    public var id: UUID { exerciseLogId }
    public var exerciseLogId: UUID
    public var date: Date
    public var measurement: MeasurementType
    public var loadMode: LoadMode
    /// Working load (external kg; body weight: net added load, negative = assistance).
    public var workingLoad: Double
    /// Total reps, or total seconds for duration exercises.
    public var totalAmount: Int
    public var bestSetAmount: Int
    /// Estimated, capped by the user's rep limit; nil when no set qualifies.
    public var estimatedOneRepMax: Double?
    public var volume: Double
    public var effectiveSets: Int
    public var isAtypical: Bool
}

public struct RecentRecord: Sendable, Hashable, Identifiable {
    public var id: String {
        "\(exerciseId.uuidString)|\(contextLabel)|\(record.kind.rawValue)|\(record.exerciseLogId.uuidString)|\(record.setIndex ?? -1)"
    }
    public var exerciseId: UUID
    public var exerciseName: String
    /// Context the record belongs to ("estándar", machine, variant).
    public var contextLabel: String
    public var record: PersonalRecord
}

public struct GoalProgress: Sendable, Hashable, Identifiable {
    public var id: UUID { goal.id }
    public var goal: Goal
    /// Best value achieved so far for the goal's metric (nil = no data yet).
    public var current: Double?
    public var fraction: Double
    public var achieved: Bool
    /// When the goal was first reached (date of the record that reached it).
    public var achievedOn: Date?
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

    /// Current vs. equivalent previous period. Running calendar periods are compared to date.
    public func comparison(_ period: StatsPeriod, now: Date, routineId: UUID? = nil) -> PeriodComparison {
        let intervals = period.comparableIntervals(now: now, calendar: calendar)
        let full = period.interval(now: now, calendar: calendar)
        return PeriodComparison(
            current: totals(in: intervals.current, routineId: routineId),
            previous: totals(in: intervals.previous, routineId: routineId),
            isToDate: intervals.current != full
        )
    }

    // MARK: Comparability classes

    /// Comparable context groups of an exercise (links respected), most recently used first.
    public func contextClasses(exerciseId: UUID) -> [ContextClass] {
        let resolver = ComparabilityResolver(links: repository.comparabilityLinks())
        var classes: [ContextClass] = []
        for entry in history.exerciseHistory(exerciseId: exerciseId) { // newest first
            let context = entry.log.context.normalized
            if let i = classes.firstIndex(where: { $0.contexts.contains(context) }) {
                classes[i].lastUsed = max(classes[i].lastUsed, entry.session.startedAt)
                continue
            }
            let members = resolver.equivalenceClass(of: entry.log.context)
            let labels = [entry.log.equipmentLabel, entry.log.variantLabel].compactMap { $0 }
            classes.append(ContextClass(
                representative: entry.log.context,
                contexts: members,
                label: labels.isEmpty ? "estándar" : labels.joined(separator: " · "),
                lastUsed: entry.session.startedAt
            ))
        }
        return classes
    }

    /// The class of the context the user trains this exercise in now (last used).
    public func currentContextClass(exerciseId: UUID) -> ContextClass? {
        contextClasses(exerciseId: exerciseId).first
    }

    private func entries(exerciseId: UUID, in contextClass: ContextClass?) -> [ExerciseHistoryEntry] {
        let all = history.exerciseHistory(exerciseId: exerciseId)
        guard let contextClass else { return all }
        return all.filter { contextClass.contexts.contains($0.log.context.normalized) }
    }

    // MARK: Exercise series

    /// One point per completed session of the exercise in one comparability class (default: the
    /// current one), inside `interval`, oldest first. Different machines/variants are never joined
    /// into one line. Atypical sessions are included but flagged (trends exclude them).
    public func exerciseSeries(exerciseId: UUID, in interval: DateInterval? = nil, contextClass: ContextClass? = nil, routineId: UUID? = nil) -> [ExercisePoint] {
        let settings = repository.settings()
        let selected = contextClass ?? currentContextClass(exerciseId: exerciseId)
        return entries(exerciseId: exerciseId, in: selected)
            .filter { (interval?.containsHalfOpen($0.session.startedAt) ?? true) && (routineId == nil || $0.session.routineId == routineId) }
            .reversed()
            .compactMap { entry -> ExercisePoint? in
                let perf = entry.performance
                guard !perf.progressionSets.isEmpty else { return nil }
                let summary = HistoryAnalyzer.summary(of: perf)
                let volume = Volume.of(perf, bodyweight: settings.bodyweightKg)
                return ExercisePoint(
                    exerciseLogId: entry.log.id,
                    date: entry.session.startedAt,
                    measurement: perf.measurement,
                    loadMode: perf.context.loadMode,
                    workingLoad: summary.workingLoad,
                    totalAmount: summary.amounts.reduce(0, +),
                    bestSetAmount: summary.amounts.max() ?? 0,
                    estimatedOneRepMax: OneRepMax.best(in: perf, settings: settings.oneRepMax).map(LoadMath.normalized),
                    volume: volume.total,
                    effectiveSets: volume.effectiveSets,
                    isAtypical: perf.isAtypical
                )
            }
    }

    // MARK: Muscles

    /// Direct and indirect sets per muscle in the interval (reported separately).
    public func muscleVolume(in interval: DateInterval, routineId: UUID? = nil) -> [MuscleSetVolume] {
        let settings = repository.settings()
        let work = history.muscleWork(in: interval, routineId: routineId)
        return MuscleVolume.compute(work, indirectFactor: settings.indirectSetFactor, calendar: calendar.calendar)
    }

    /// Weekly direct and indirect sets for one muscle over the last `weeks` weeks (oldest first).
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

    /// Records of one comparability class (default: the current one). Records of different
    /// machines/variants are never mixed.
    public func records(exerciseId: UUID, contextClass: ContextClass? = nil) -> RecordSummary {
        let selected = contextClass ?? currentContextClass(exerciseId: exerciseId)
        return PersonalRecords.compute(
            entries(exerciseId: exerciseId, in: selected).map(\.performance),
            oneRepMax: repository.settings().oneRepMax,
            bodyweight: repository.settings().bodyweightKg
        )
    }

    /// Records *broken* within the last `days` days, newest first: a record counts only if a
    /// previous record of the same kind and context existed; one entry per (exercise, context,
    /// kind, session) with the best value of that session.
    public func recentRecords(days: Int, now: Date, limit: Int = 5) -> [RecentRecord] {
        let since = calendar.addDays(-days, to: calendar.day(of: now))
        var result: [RecentRecord] = []
        for exercise in repository.exercises() where repository.hasHistory(exerciseId: exercise.id) {
            for contextClass in contextClasses(exerciseId: exercise.id) {
                let summary = records(exerciseId: exercise.id, contextClass: contextClass)
                var bestPerSessionKind: [String: PersonalRecord] = [:]
                // Session (log) where each kind was first recorded: values from that session are the
                // starting point, not records broken.
                var firstLogOfKind: [RecordKind: UUID] = [:]
                for record in summary.history {
                    let first = firstLogOfKind[record.kind] ?? record.exerciseLogId
                    firstLogOfKind[record.kind] = first
                    guard record.exerciseLogId != first, record.date >= since, record.date <= now else { continue }
                    let key = "\(record.kind.rawValue)|\(record.exerciseLogId.uuidString)"
                    if let existing = bestPerSessionKind[key], existing.value >= record.value { continue }
                    bestPerSessionKind[key] = record
                }
                result += bestPerSessionKind.values.map {
                    RecentRecord(exerciseId: exercise.id, exerciseName: exercise.name, contextLabel: contextClass.label, record: $0)
                }
            }
        }
        return Array(result.sorted { a, b in
            a.record.date != b.record.date ? a.record.date > b.record.date : a.id < b.id
        }.prefix(limit))
    }

    /// Progress of every goal, measured in the exercise's current comparability class.
    public func goalProgress(now: Date) -> [GoalProgress] {
        repository.goals().map { goal in
            let summary = records(exerciseId: goal.exerciseId)
            let current: Double?
            var reachedOn: Date?
            switch goal.metric {
            case .weight:
                current = summary.maxWeight?.value
                reachedOn = summary.history.first { $0.kind == .maxWeight && $0.value >= goal.value }?.date
            case .estimatedOneRepMax:
                current = summary.bestEstimatedOneRepMax?.value
                reachedOn = summary.history.first { $0.kind == .bestEstimatedOneRepMax && $0.value >= goal.value }?.date
            case .sessionVolume:
                current = summary.maxSessionVolume?.value
                reachedOn = summary.history.first { $0.kind == .maxSessionVolume && $0.value >= goal.value }?.date
            case .repsAtWeight:
                let eligible = goal.weight.map { w in summary.maxRepsAtWeight.filter { ($0.weight ?? 0) >= w - LoadMath.resolution } } ?? []
                current = eligible.map(\.value).max()
                reachedOn = eligible.filter { $0.value >= goal.value }.map(\.date).min()
            }
            let achieved = (current ?? 0) >= goal.value && goal.value > 0
            let fraction = current.map { goal.value > 0 ? min(1, $0 / goal.value) : 0 } ?? 0
            return GoalProgress(goal: goal, current: current, fraction: fraction, achieved: achieved, achievedOn: achieved ? reachedOn : nil)
        }
    }

    /// Marks reached goals as achieved, dated when the record reached them. Returns the new ones.
    @discardableResult
    public func refreshGoals(now: Date) throws -> [Goal] {
        var achieved: [Goal] = []
        for progress in goalProgress(now: now) where progress.achieved && progress.goal.status == .active {
            var g = progress.goal
            g.status = .achieved
            g.achievedAt = progress.achievedOn ?? now
            try repository.upsertGoal(g)
            achieved.append(g)
        }
        return achieved
    }
}

extension ComparabilityContext {
    /// Stable identifier for UI lists.
    public var sortKeyForUI: String { sortKey }
}
