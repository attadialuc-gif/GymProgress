import Foundation
import Testing
@testable import GymCore

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, tz: String) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tz)!
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private let ba = "America/Argentina/Buenos_Aires"
private let ny = "America/New_York"

@Suite("Dates (8.6)")
struct DateTests {
    let baCal = TrainingCalendar(timeZone: TimeZone(identifier: ba)!)
    let nyCal = TrainingCalendar(timeZone: TimeZone(identifier: ny)!)

    @Test("A session crossing midnight belongs to the day it started")
    func crossesMidnight() {
        let start = date(2026, 3, 10, 23, 30, tz: ba)
        #expect(baCal.day(of: start) == date(2026, 3, 10, 0, 0, tz: ba))
        #expect(baCal.daysBetween(start, date(2026, 3, 11, 0, 40, tz: ba)) == 1)
    }

    @Test("DST spring forward: adding a day keeps local midnight, day count is 1")
    func dstSpringForward() {
        let before = date(2026, 3, 7, 0, 0, tz: ny)
        let after = nyCal.addDays(1, to: nyCal.addDays(1, to: before))
        #expect(after == date(2026, 3, 9, 0, 0, tz: ny))
        #expect(nyCal.daysBetween(date(2026, 3, 7, 22, tz: ny), date(2026, 3, 8, 7, tz: ny)) == 1)
        // The DST day has 23 hours.
        let d8 = date(2026, 3, 8, 0, 0, tz: ny)
        #expect(nyCal.addDays(1, to: d8).timeIntervalSince(d8) == 23 * 3600)
    }

    @Test("DST fall back: the 25-hour day is still one day; weeks still have 7 days")
    func dstFallBack() {
        let d = date(2026, 11, 1, 0, 0, tz: ny)
        #expect(nyCal.addDays(1, to: d).timeIntervalSince(d) == 25 * 3600)
        let week = nyCal.daysOfWeek(containing: d)
        #expect(week.count == 7)
        #expect(Set(week.map { nyCal.weekday(of: $0) }).count == 7)
    }

    @Test("Time zone change: the same instant falls on the day of the calendar used")
    func timeZoneChange() {
        let instant = date(2026, 5, 20, 1, 30, tz: "UTC") // 22:30 on May 19 in Buenos Aires
        let utcCal = TrainingCalendar(timeZone: TimeZone(identifier: "UTC")!)
        #expect(utcCal.day(of: instant) == date(2026, 5, 20, 0, 0, tz: "UTC"))
        #expect(baCal.day(of: instant) == date(2026, 5, 19, 0, 0, tz: ba))
    }

    @Test("Configurable start of week: Monday (default) vs Sunday")
    func weekStart() {
        let wednesday = date(2026, 10, 14, tz: ba)
        #expect(baCal.weekStart(of: wednesday) == date(2026, 10, 12, 0, 0, tz: ba))
        let sundayCal = TrainingCalendar(timeZone: TimeZone(identifier: ba)!, firstWeekday: 1)
        #expect(sundayCal.weekStart(of: wednesday) == date(2026, 10, 11, 0, 0, tz: ba))
        // A Sunday belongs to the previous week with Monday start, to the new one with Sunday start.
        let sunday = date(2026, 10, 18, tz: ba)
        #expect(baCal.weekStart(of: sunday) == date(2026, 10, 12, 0, 0, tz: ba))
        #expect(sundayCal.weekStart(of: sunday) == date(2026, 10, 18, 0, 0, tz: ba))
    }

    @Test("End of month and end of year: weeks spanning the boundary")
    func monthAndYearBoundaries() {
        let newYear = date(2027, 1, 1, tz: ba) // Friday
        #expect(baCal.weekStart(of: newYear) == date(2026, 12, 28, 0, 0, tz: ba))
        #expect(baCal.daysOfWeek(containing: newYear).last == date(2027, 1, 3, 0, 0, tz: ba))
        #expect(baCal.daysInMonth(containing: date(2026, 2, 10, tz: ba)).count == 28)
        #expect(baCal.daysInMonth(containing: date(2028, 2, 10, tz: ba)).count == 29)
        #expect(baCal.daysBetween(date(2026, 12, 31, 23, tz: ba), date(2027, 1, 1, 1, tz: ba)) == 1)
    }
}

@Suite("Schedule and streaks (8.5)")
struct StreakTests {
    let cal = TrainingCalendar(timeZone: TimeZone(identifier: ba)!)
    let routineA = Fx.uuid(0xA)
    let routineB = Fx.uuid(0xB)

    func session(_ n: Int, _ d: Date, sets: Int = 9, status: SessionStatus = .completed) -> SessionDigest {
        SessionDigest(id: Fx.uuid(n), start: d, status: status, effectiveSets: sets)
    }

    /// Mon/Wed/Fri plan from 2026-10-05.
    var monWedFri: [ScheduleEntry] {
        [2, 4, 6].enumerated().map { i, wd in
            ScheduleEntry(id: Fx.uuid(100 + i), weekday: wd, routineId: routineA, validFrom: date(2026, 10, 5, 0, 0, tz: ba), createdAt: date(2026, 10, 1, tz: ba))
        }
    }

    @Test("Valid session requires completed + minimum effective sets")
    func validSession() {
        #expect(session(1, Date(), sets: 3).isValid(minSets: 3))
        #expect(!session(1, Date(), sets: 2).isValid(minSets: 3))
        #expect(!session(1, Date(), sets: 9, status: .active).isValid(minSets: 3))
        #expect(!session(1, Date(), sets: 9, status: .discarded).isValid(minSets: 3))
    }

    @Test("validFrom: changing the schedule never rewrites the past")
    func scheduleHistory() {
        var entries = monWedFri
        // From 2026-10-19: Wednesday becomes rest, Tuesday gets routine B.
        let change = date(2026, 10, 19, 0, 0, tz: ba)
        entries.append(ScheduleEntry(id: Fx.uuid(200), weekday: 4, routineId: nil, validFrom: change, createdAt: change))
        entries.append(ScheduleEntry(id: Fx.uuid(201), weekday: 3, routineId: routineB, validFrom: change, createdAt: change))

        #expect(Schedule.plannedRoutine(on: date(2026, 10, 14, tz: ba), entries: entries, calendar: cal) == routineA)
        #expect(Schedule.plannedRoutine(on: date(2026, 10, 21, tz: ba), entries: entries, calendar: cal) == nil)
        #expect(Schedule.plannedRoutine(on: date(2026, 10, 20, tz: ba), entries: entries, calendar: cal) == routineB)
        #expect(Schedule.plannedRoutine(on: date(2026, 10, 13, tz: ba), entries: entries, calendar: cal) == nil)
        #expect(Schedule.plannedDays(inWeekOf: date(2026, 10, 14, tz: ba), entries: entries, calendar: cal).count == 3)
        #expect(Schedule.plannedDays(inWeekOf: date(2026, 10, 21, tz: ba), entries: entries, calendar: cal).count == 3)
        // Before the first entry nothing was planned.
        #expect(Schedule.plannedDays(inWeekOf: date(2026, 9, 30, tz: ba), entries: entries, calendar: cal).isEmpty)
    }

    @Test("Mode A: weeks meeting the plan; scheduled rest days are not failures; current week is neutral")
    func weeklyMode() {
        let sessions = [
            // Week of Oct 5: Mon, Wed, Fri → met
            session(1, date(2026, 10, 5, 18, tz: ba)), session(2, date(2026, 10, 7, 18, tz: ba)), session(3, date(2026, 10, 9, 18, tz: ba)),
            // Week of Oct 12: Mon, Tue (not planned day but counts), Sat → 3 ≥ 3 met
            session(4, date(2026, 10, 12, 18, tz: ba)), session(5, date(2026, 10, 13, 18, tz: ba)), session(6, date(2026, 10, 17, 10, tz: ba)),
            // Week of Oct 19: only Mon, and one too-short session → missed
            session(7, date(2026, 10, 19, 18, tz: ba)), session(8, date(2026, 10, 21, 18, tz: ba), sets: 1),
            // Week of Oct 26: Mon, Wed, Fri → met
            session(9, date(2026, 10, 26, 18, tz: ba)), session(10, date(2026, 10, 28, 18, tz: ba)), session(11, date(2026, 10, 30, 18, tz: ba)),
            // Current week (Nov 2): Monday only so far
            session(12, date(2026, 11, 2, 18, tz: ba)),
        ]
        let weeks = Streaks.weeklyCompliance(sessions: sessions, schedule: monWedFri, minSets: 3, now: date(2026, 11, 3, 12, tz: ba), calendar: cal)
        #expect(weeks.map(\.status) == [.met, .met, .missed, .met, .inProgress])
        let streak = Streaks.weeklyStreak(weeks)
        #expect(streak.current == 1)
        #expect(streak.best == 2)
    }

    @Test("Mode A: a week with no planned days is neutral")
    func weeklyNoPlanNeutral() {
        let weeks: [WeekCompliance] = [
            .init(weekStart: Date(), planned: 3, valid: 3, status: .met),
            .init(weekStart: Date(), planned: 0, valid: 0, status: .noPlan),
            .init(weekStart: Date(), planned: 3, valid: 4, status: .met),
        ]
        #expect(Streaks.weeklyStreak(weeks).current == 2)
    }

    @Test("Mode B: gap ≤ K days keeps the chain (K = 2)")
    func dayGapMode() {
        let days = [
            date(2026, 10, 1, tz: ba), date(2026, 10, 3, tz: ba), date(2026, 10, 5, tz: ba), // chain of 3
            date(2026, 10, 9, tz: ba), date(2026, 10, 10, tz: ba),                            // gap 4 → new chain of 2
        ].map { cal.day(of: $0) }
        let alive = Streaks.dayGapStreak(trainingDays: days, maxGapDays: 2, now: date(2026, 10, 12, tz: ba), calendar: cal)
        #expect(alive.current == 2)
        #expect(alive.best == 3)
        let broken = Streaks.dayGapStreak(trainingDays: days, maxGapDays: 2, now: date(2026, 10, 13, tz: ba), calendar: cal)
        #expect(broken.current == 0)
        #expect(broken.best == 3)
    }

    @Test("Several sessions in one day count as one training day")
    func oneTrainingDayPerDay() {
        let sessions = [session(1, date(2026, 10, 1, 8, tz: ba)), session(2, date(2026, 10, 1, 19, tz: ba))]
        #expect(Streaks.trainingDays(sessions, minSets: 3, calendar: cal).count == 1)
    }

    @Test("Weekly goal progress never exceeds 100 %")
    func weeklyGoal() {
        let sessions = (0..<5).map { session($0, date(2026, 10, 12 + $0, 18, tz: ba)) }
        let p = Streaks.weeklyGoalProgress(sessions: sessions, goal: 3, minSets: 3, now: date(2026, 10, 16, 20, tz: ba), calendar: cal)
        #expect(p.done == 5)
        #expect(p.fraction == 1)
    }
}

@Suite("Weight parsing and validation")
struct ParsingTests {
    @Test("Comma and dot are both decimal separators", arguments: [
        ("62,5", 62.5), ("62.5", 62.5), (" 62,50 ", 62.5), ("60", 60), ("0,25", 0.25), (",5", 0.5), ("100.", 100),
    ] as [(String, Double)])
    func accepted(text: String, expected: Double) {
        #expect(WeightParser.parse(text) == expected)
    }

    @Test("Invalid input is rejected", arguments: ["", "abc", "6,2,5", "1.000,5", "-5", "+5", "62 ,5", ".", "1e3"])
    func rejected(text: String) {
        #expect(WeightParser.parse(text) == nil)
    }

    @Test("Integers for reps")
    func ints() {
        #expect(WeightParser.parseInt("12") == 12)
        #expect(WeightParser.parseInt("12,5") == nil)
        #expect(WeightParser.parseInt("-3") == nil)
    }

    @Test("Negative values are errors; unusual values are warnings that don't block")
    func validation() {
        #expect(SetValidator.validate(weight: -1, reps: 5, seconds: nil, rir: nil, rpe: nil).contains { $0.isError })
        let unusual = SetValidator.validate(weight: 600, reps: 150, seconds: nil, rir: nil, rpe: nil)
        #expect(unusual.count == 2)
        #expect(!unusual.contains { $0.isError })
        #expect(SetValidator.validate(weight: 60, reps: 10, seconds: nil, rir: 2, rpe: 8).isEmpty)
        #expect(SetValidator.validate(weight: 60, reps: 10, seconds: nil, rir: 11, rpe: nil).contains { $0.isError })
    }

    @Test("es-AR formatting uses comma decimals")
    func formatting() {
        #expect(GymFormat.kg(62.5) == "62,5 kg")
        #expect(GymFormat.kg(60) == "60 kg")
        #expect(GymFormat.kg(62.5, locale: Locale(identifier: "en_US")) == "62.5 kg")
    }
}
