import Foundation
import Testing
@testable import GymCore
@testable import GymStore

@MainActor
@Suite("Stage 5 — calendar, streaks, weekly goal")
struct ConsistencyServiceTests {

    /// SFx.day(0) is Monday 2026-01-05 (Buenos Aires).
    func setUp() throws -> (TestStore, RoutineTemplate, ConsistencyService) {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        let consistency = ConsistencyService(repository: store.repo, timeZone: SFx.tz)
        try consistency.setWeeklyPlan([2: routine.id, 4: routine.id, 6: routine.id], from: SFx.day(0), now: SFx.day(0))
        return (store, routine, consistency)
    }

    @Test("Week view: completed, missed, planned and rest days; the past keeps its plan after a change")
    func calendarDays() throws {
        let (store, routine, consistency) = try setUp()
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10]) // Mon

        let week = consistency.week(containing: SFx.day(0), now: SFx.day(3)) // now = Thursday
        #expect(week.map(\.status) == [.completed, .rest, .missed, .rest, .planned, .rest, .rest])
        #expect(week[0].plannedRoutineName == "Torso A")
        #expect(week[3].isToday)

        try SFx.performSession(store, routineId: routine.id, day: 4, weight: 60, reps: [10, 10, 10]) // Fri

        // From next Monday the plan becomes Tuesday only; this week is untouched.
        try consistency.setWeeklyPlan([3: routine.id], from: SFx.day(7), now: SFx.day(5))
        let past = consistency.week(containing: SFx.day(0), now: SFx.day(8))
        #expect(past.map(\.status) == [.completed, .rest, .missed, .rest, .completed, .rest, .rest])
        let next = consistency.week(containing: SFx.day(7), now: SFx.day(5))
        #expect(next.map(\.status) == [.rest, .planned, .rest, .rest, .rest, .rest, .rest])
        #expect(consistency.month(containing: SFx.day(0), now: SFx.day(3)).count == 31)
    }

    @Test("Weekly goal and streak mode A (plan) and B (day gap) with their definitions")
    func streaksAndGoal() throws {
        let (store, routine, consistency) = try setUp()
        for d in [0, 2, 4] {
            try SFx.performSession(store, routineId: routine.id, day: d, weight: 60, reps: [10, 10, 10])
        }
        let week = consistency.weekSummary(now: SFx.day(5))
        #expect(week.planned == 3)
        #expect(week.validSessions == 3)
        #expect(week.goalMet)
        #expect(week.goalFraction == 1)

        let a = consistency.streak(now: SFx.day(8))
        #expect(a.result.mode == .weeklyPlan)
        #expect(a.result.current == 1)
        #expect(a.definition.contains("Semanas seguidas"))

        var settings = store.repo.settings()
        settings.streakMode = .dayGap
        settings.maxGapDays = 2
        try store.repo.saveSettings(settings)
        let b = consistency.streak(now: SFx.day(5))
        #expect(b.result.mode == .dayGap)
        #expect(b.result.current == 3)
        #expect(consistency.streak(now: SFx.day(8)).result.current == 0)
        #expect(b.definition.contains("2 días"))
    }

    @Test("Sessions below the minimum effective sets don't count as training days")
    func invalidSessionsDoNotCount() throws {
        let (store, routine, consistency) = try setUp()
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10]) // 1 set only
        let week = consistency.week(containing: SFx.day(0), now: SFx.day(1))
        #expect(week[0].status == .missed)
        #expect(consistency.weekSummary(now: SFx.day(1)).validSessions == 0)
    }
}

@MainActor
@Suite("Stage 6 — statistics")
struct StatsServiceTests {

    func setUp() throws -> (TestStore, Exercise, StatsService) {
        let store = try TestStore()
        let bench = try SFx.bench(in: store)
        let routine = try SFx.routine(with: bench, in: store)
        try SFx.performSession(store, routineId: routine.id, day: 0, weight: 60, reps: [10, 10, 10], rir: [2, 2, 2])
        try SFx.performSession(store, routineId: routine.id, day: 2, weight: 60, reps: [11, 10, 10], rir: [2, 2, 2])
        try SFx.performSession(store, routineId: routine.id, day: 8, weight: 62.5, reps: [10, 9, 8], rir: [2, 2, 2])
        return (store, bench, StatsService(repository: store.repo, timeZone: SFx.tz))
    }

    @Test("Period intervals and their equivalent previous periods")
    func periods() throws {
        let (_, _, stats) = try setUp()
        let cal = stats.calendar
        let now = SFx.day(3) // Thursday 2026-01-08
        let week = StatsPeriod.week.interval(now: now, calendar: cal)
        #expect(week.start == cal.day(of: SFx.day(0)))
        #expect(StatsPeriod.week.previousInterval(now: now, calendar: cal).end == week.start)
        #expect(cal.daysBetween(StatsPeriod.last30Days.interval(now: now, calendar: cal).start, StatsPeriod.last30Days.interval(now: now, calendar: cal).end) == 30)
        let month = StatsPeriod.calendarMonth.interval(now: now, calendar: cal)
        #expect(cal.calendar.component(.day, from: month.start) == 1)
        #expect(cal.daysBetween(month.start, month.end) == 31)
        let prevMonth = StatsPeriod.calendarMonth.previousInterval(now: now, calendar: cal)
        #expect(cal.calendar.component(.month, from: prevMonth.start) == 12)
    }

    @Test("Totals and comparison with the previous week come from recorded sets")
    func totalsAndComparison() throws {
        let (_, _, stats) = try setUp()
        let comparison = stats.comparison(.week, now: SFx.day(9))
        #expect(comparison.current.validSessions == 1)
        #expect(comparison.current.effectiveSets == 3)
        #expect(comparison.current.volume == 62.5 * 27)
        #expect(comparison.previous.validSessions == 2)
        #expect(comparison.previous.volume == 60 * 61)
        #expect(comparison.previous.trainingDays == 2)
    }

    @Test("Exercise series: one point per session with load, reps and capped e1RM")
    func exerciseSeries() throws {
        let (_, bench, stats) = try setUp()
        let points = stats.exerciseSeries(exerciseId: bench.id)
        #expect(points.map(\.workingLoad) == [60, 60, 62.5])
        #expect(points.map(\.totalAmount) == [30, 31, 27])
        #expect(points[0].estimatedOneRepMax == 80)
        #expect(points[1].estimatedOneRepMax == 80) // 11 reps excluded by the cap, 10 reps → 80
        // 62.5 × (1 + 10/30) = 83.333…, stored at 1 g resolution.
        #expect(points[2].estimatedOneRepMax == 83.333)
    }

    @Test("Muscle volume by period: direct and indirect separate")
    func muscles() throws {
        let (_, _, stats) = try setUp()
        let week = StatsPeriod.week.interval(now: SFx.day(1), calendar: stats.calendar)
        let volume = stats.muscleVolume(in: week)
        let chest = try #require(volume.first { $0.muscle == .chest })
        #expect(chest.directSets == 6)
        #expect(chest.frequencyDays == 2)
        let triceps = try #require(volume.first { $0.muscle == .triceps })
        #expect(triceps.directSets == 0)
        #expect(triceps.indirectSets == 3)
        let weekly = stats.weeklyDirectSets(muscle: .chest, weeks: 2, now: SFx.day(9))
        #expect(weekly.map(\.directSets) == [6, 3])
    }

    @Test("Recent records: broken records only (not the first session's), real vs estimated labeled")
    func recentRecords() throws {
        let (_, _, stats) = try setUp()
        let recent = stats.recentRecords(days: 30, now: SFx.day(9))
        #expect(recent.contains { $0.record.kind == .maxWeight && $0.record.value == 62.5 && !$0.record.isEstimated })
        #expect(recent.contains { $0.record.kind == .bestEstimatedOneRepMax && $0.record.isEstimated })
        #expect(!recent.contains { $0.record.date == SFx.day(0) })
    }

    @Test("Goals: progress from real records and automatic achievement")
    func goals() throws {
        let (store, bench, stats) = try setUp()
        try store.repo.upsertGoal(Goal(exerciseId: bench.id, metric: .weight, value: 62.5, createdAt: SFx.day(0)))
        try store.repo.upsertGoal(Goal(exerciseId: bench.id, metric: .repsAtWeight, value: 12, weight: 60, createdAt: SFx.day(0)))
        let progress = stats.goalProgress(now: SFx.day(9))
        #expect(progress.first { $0.goal.metric == .weight }?.achieved == true)
        let reps = try #require(progress.first { $0.goal.metric == .repsAtWeight })
        #expect(reps.current == 11)
        #expect(!reps.achieved)
        let achieved = try stats.refreshGoals(now: SFx.day(9))
        #expect(achieved.count == 1)
        #expect(store.repo.goals().first { $0.metric == .weight }?.status == .achieved)
    }
}
