import Foundation
import GymCore

/// Metrics (1RM, volume, muscles, records, trend), calendar/consistency and parsing/formatting
/// fixtures, mirroring MetricsTests and ConsistencyAndDateTests plus extra edge cases.
enum CoreFixtures {
    struct MuscleWorkDTO: Codable {
        var performance: ExercisePerformance
        var primary: [MuscleGroup]
        var secondary: [MuscleInvolvement]
        var work: MuscleWork { MuscleWork(performance: performance, primary: primary, secondary: secondary) }
    }

    static func metrics() -> [String: Any] {
        let epley = OneRepMaxSettings(formula: .epley)
        let brzycki = OneRepMaxSettings(formula: .brzycki)
        let capped12 = OneRepMaxSettings(formula: .epley, maxReps: 12)
        let estimateCases: [(Double, Int, OneRepMaxSettings)] = [
            (100, 1, epley), (100, 5, epley), (60, 10, epley), (80, 3, epley), (60, 11, epley), (60, 12, capped12),
            (0, 5, epley), (60, 0, epley), (100, 1, brzycki), (100, 5, brzycki), (60, 10, brzycki), (62.5, 8, epley),
        ]
        let rawCases: [(Double, Int, OneRepMaxFormula)] = [(60, 37, .brzycki), (60, 36, .brzycki), (60, 40, .epley), (-5, 3, .epley)]

        var best = FX.perf(1, day: 0, weight: 100, reps: [5, 3])
        best.sets.append(PerformedSet(index: 2, kind: .warmup, status: .completed, weight: 140, reps: 1))
        best.sets.append(PerformedSet(index: 3, kind: .working, status: .pending, weight: 150, reps: 1))
        best.sets.append(PerformedSet(index: 4, kind: .working, status: .completed, weight: 130, reps: 1, excludedFromEstimates: true))

        var external = FX.perf(1, day: 0, weight: 60, reps: [10, 9, 8])
        external.sets.append(PerformedSet(index: 3, kind: .warmup, status: .completed, weight: 40, reps: 10))
        external.sets.append(PerformedSet(index: 4, kind: .working, status: .pending, weight: 60, reps: 10))
        external.sets.append(PerformedSet(index: 5, kind: .dropSet, status: .completed, weight: 40, reps: 6))
        let perSide = FX.perf(1, day: 0, weight: 12.5, reps: [10, 10], context: ComparabilityContext(exerciseId: FX.curlId, loadMode: .perSide))
        func pullUps(_ added: Double?, _ assistance: Double?) -> ExercisePerformance {
            ExercisePerformance(sessionId: FX.uuid(1), exerciseLogId: FX.uuid(2), sessionStart: FX.day(0),
                                context: ComparabilityContext(exerciseId: FX.pullUpId, loadMode: .total), measurement: .bodyweightReps,
                                sets: [PerformedSet(index: 0, reps: 10, addedWeight: added, assistance: assistance),
                                       PerformedSet(index: 1, reps: 8, addedWeight: added, assistance: assistance)])
        }
        let duration = ExercisePerformance(sessionId: FX.uuid(1), exerciseLogId: FX.uuid(2), sessionStart: FX.day(0),
                                           context: ComparabilityContext(exerciseId: FX.plankId, loadMode: .total), measurement: .duration,
                                           sets: [PerformedSet(index: 0, seconds: 45), PerformedSet(index: 1, seconds: 40)])
        let volumeCases: [(ExercisePerformance, Double?)] = [
            (external, nil), (perSide, nil), (pullUps(10, nil), 80), (pullUps(nil, 20), 80), (pullUps(10, nil), nil),
            (pullUps(nil, nil), nil), (duration, nil), (pullUps(nil, 100), 80),
        ]

        let benchWork = MuscleWorkDTO(performance: FX.perf(1, day: 0, weight: 60, reps: [10, 10, 10]), primary: [.chest],
                                      secondary: [MuscleInvolvement(muscle: .triceps), MuscleInvolvement(muscle: .frontDelts, factor: 0.3)])
        let dipsWork = MuscleWorkDTO(performance: FX.perf(2, day: 2, weight: 0, reps: [10, 10]), primary: [.triceps],
                                     secondary: [MuscleInvolvement(muscle: .chest)])
        var warmPerf = FX.perf(1, day: 0, weight: 60, reps: [10])
        warmPerf.sets.append(PerformedSet(index: 1, kind: .warmup, status: .completed, weight: 20, reps: 10))
        let selfSecondary = MuscleWorkDTO(performance: warmPerf, primary: [.chest], secondary: [MuscleInvolvement(muscle: .chest)])
        let discarded = MuscleWorkDTO(performance: FX.perf(3, day: 1, weight: 50, reps: [10, 10], status: .discarded), primary: [.quads], secondary: [])
        let muscleCases: [([MuscleWorkDTO], Double)] = [([benchWork, dipsWork], 0.5), ([selfSecondary], 0.5), ([benchWork, dipsWork, discarded], 0.25)]

        let recordsHistory = [
            FX.perf(1, day: 0, weight: 60, reps: [10, 10, 10]),
            FX.perf(2, day: 3, weight: 62.5, reps: [8, 8, 7]),
            FX.perf(3, day: 6, weight: 62.5, reps: [8, 8, 8]),
            FX.perf(4, day: 9, weight: 60, reps: [12, 11, 10]),
        ]
        let recordCases: [([ExercisePerformance], OneRepMaxSettings)] = [
            (recordsHistory, .default), ([], .default), ([FX.perf(1, day: 0, weight: 200, reps: [1], status: .discarded)], .default),
            (recordsHistory.reversed(), OneRepMaxSettings(formula: .brzycki, maxReps: 12)),
        ]

        let trendValues: [[Double]] = [[100, 90], [], [80, 82, 84, 86], [80, 80.5, 80, 80.2], [80, 86, 79, 85, 80], [86, 84, 82, 80],
                                       [84, 79.17, 81.25], [0, 0, 0], [50, 51, 52, 53, 54, 55, 56, 57, 40]]
        let trendPerformances: [[ExercisePerformance]] = [
            [FX.perf(1, day: 0, weight: 60, reps: [11, 11, 11]), FX.perf(2, day: 2, weight: 60, reps: [12, 11, 11]), FX.perf(3, day: 4, weight: 60, reps: [12, 12, 12])],
            [FX.perf(1, day: 0, weight: 60, reps: [10, 9, 9]), FX.perf(2, day: 2, weight: 60, reps: [10, 10, 9]), FX.perf(3, day: 4, weight: 60, reps: [11, 10, 10])],
            [FX.perf(1, day: 0, weight: 55, reps: [10, 10]), FX.perf(2, day: 2, weight: 60, reps: [8, 8]), FX.perf(3, day: 4, weight: 62.5, reps: [6, 6])],
            [FX.perf(1, day: 0, weight: 55, reps: [12, 12]), FX.perf(2, day: 2, weight: 60, reps: [8, 8]), FX.perf(3, day: 4, weight: 62.5, reps: [6, 6])],
        ]

        return [
            "oneRepMaxEstimate": estimateCases.map { c in
                ["weight": c.0, "reps": c.1, "settings": json(c.2), "estimate": OneRepMax.estimate(weight: c.0, reps: c.1, settings: c.2).map { $0 as Any } ?? NSNull()]
            },
            "oneRepMaxRaw": rawCases.map { c in
                ["weight": c.0, "reps": c.1, "formula": c.2.rawValue, "raw": OneRepMax.raw(weight: c.0, reps: c.1, formula: c.2).map { $0 as Any } ?? NSNull()]
            },
            "oneRepMaxBest": [["performance": json(best), "settings": json(OneRepMaxSettings.default), "best": OneRepMax.best(in: best).map { $0 as Any } ?? NSNull()]],
            "volume": volumeCases.map { c in
                ["performance": json(c.0), "bodyweight": c.1.map { $0 as Any } ?? NSNull(), "result": json(Volume.of(c.0, bodyweight: c.1))]
            },
            "muscleVolume": muscleCases.map { c in
                ["work": json(c.0), "indirectFactor": c.1, "timeZone": "UTC",
                 "result": json(MuscleVolume.compute(c.0.map(\.work), indirectFactor: c.1, calendar: FX.utcCalendar))]
            },
            "records": recordCases.map { c in
                ["performances": json(c.0), "settings": json(c.1), "result": json(PersonalRecords.compute(c.0, oneRepMax: c.1))]
            },
            "trendValues": trendValues.map { ["values": $0, "result": TrendAnalyzer.classify($0).rawValue] },
            "trendPerformances": trendPerformances.map { ["performances": json($0), "result": TrendAnalyzer.classify(performances: $0).rawValue] },
        ]
    }

    // MARK: Calendar, schedule, streaks

    static func consistency() -> [String: Any] {
        let ba = FX.ba, ny = FX.ny
        let cals: [(String, Int)] = [(ba, 2), (ba, 1), (ny, 2), ("UTC", 2), ("Europe/Madrid", 2),
                                     ("America/Santiago", 2), ("Asia/Beirut", 1), ("America/Havana", 2)]
        let instants: [Date] = [
            FX.date(2026, 3, 10, 23, 30, tz: ba), FX.date(2026, 3, 11, 0, 40, tz: ba), FX.date(2026, 3, 7, 0, 0, tz: ny),
            FX.date(2026, 3, 8, 0, 0, tz: ny), FX.date(2026, 3, 8, 7, tz: ny), FX.date(2026, 11, 1, 0, 0, tz: ny),
            FX.date(2026, 5, 20, 1, 30, tz: "UTC"), FX.date(2026, 10, 14, tz: ba), FX.date(2026, 10, 18, tz: ba),
            FX.date(2027, 1, 1, tz: ba), FX.date(2026, 2, 10, tz: ba), FX.date(2028, 2, 10, tz: ba),
            FX.date(2026, 12, 31, 23, tz: ba), FX.date(2026, 3, 29, 1, 30, tz: "Europe/Madrid"), FX.date(2026, 10, 25, 2, 30, tz: "Europe/Madrid"),
            // Midnight DST transitions (day starts at 01:00, or 23:00 repeated).
            FX.date(2026, 9, 6, 0, 30, tz: "America/Santiago"), FX.date(2026, 4, 5, 0, 30, tz: "America/Santiago"),
            FX.date(2026, 9, 5, 22, 0, tz: "America/Santiago"), FX.date(2026, 3, 29, 0, 30, tz: "Asia/Beirut"),
            FX.date(2026, 10, 24, 23, 30, tz: "Asia/Beirut"), FX.date(2026, 3, 8, 0, 30, tz: "America/Havana"),
            FX.date(2026, 10, 31, 23, 30, tz: "America/Havana"),
        ]
        var calendarCases: [[String: Any]] = []
        for (tz, fw) in cals {
            let cal = TrainingCalendar(timeZone: TimeZone(identifier: tz)!, firstWeekday: fw)
            for (i, d) in instants.enumerated() {
                let next = instants[(i + 1) % instants.count]
                calendarCases.append([
                    "timeZone": tz, "firstWeekday": fw, "date": d.timeIntervalSince1970,
                    "day": cal.day(of: d).timeIntervalSince1970,
                    "weekday": cal.weekday(of: d),
                    "weekStart": cal.weekStart(of: d).timeIntervalSince1970,
                    "addDays": [-7, -1, 1, 2, 30].map { ["days": $0, "result": cal.addDays($0, to: cal.day(of: d)).timeIntervalSince1970] },
                    "daysBetweenNext": ["other": next.timeIntervalSince1970, "result": cal.daysBetween(d, next)],
                    "daysOfWeek": cal.daysOfWeek(containing: d).map(\.timeIntervalSince1970),
                    "startOfMonth": cal.startOfMonth(d).timeIntervalSince1970,
                    "daysInMonthCount": cal.daysInMonth(containing: d).count,
                ])
            }
        }

        let cal = TrainingCalendar(timeZone: TimeZone(identifier: ba)!)
        let routineA = FX.uuid(0xA), routineB = FX.uuid(0xB)
        let monWedFri = [2, 4, 6].enumerated().map { i, wd in
            ScheduleEntry(id: FX.uuid(100 + i), weekday: wd, routineId: routineA, validFrom: FX.date(2026, 10, 5, 0, 0, tz: ba), createdAt: FX.date(2026, 10, 1, tz: ba))
        }
        let change = FX.date(2026, 10, 19, 0, 0, tz: ba)
        let changed = monWedFri + [
            ScheduleEntry(id: FX.uuid(200), weekday: 4, routineId: nil, validFrom: change, createdAt: change),
            ScheduleEntry(id: FX.uuid(201), weekday: 3, routineId: routineB, validFrom: change, createdAt: change),
        ]
        var counter = 300
        let snapshotChange = FX.date(2026, 10, 19, 9, tz: ba)
        let newPlan = Schedule.weeklyPlanEntries(assignments: [2: routineA, 5: routineB], validFrom: snapshotChange, createdAt: snapshotChange, calendar: cal) {
            counter += 1
            return FX.uuid(counter)
        }
        // A plan saved earlier for a later date vs. a later decision (latest created wins).
        let futureFirst = [
            ScheduleEntry(id: FX.uuid(400), weekday: 2, routineId: routineA, validFrom: FX.date(2026, 11, 2, 0, 0, tz: ba), createdAt: FX.date(2026, 10, 1, tz: ba)),
            ScheduleEntry(id: FX.uuid(401), weekday: 2, routineId: nil, validFrom: FX.date(2026, 10, 6, 0, 0, tz: ba), createdAt: FX.date(2026, 10, 2, tz: ba)),
            ScheduleEntry(id: FX.uuid(402), weekday: 4, routineId: routineB, validFrom: FX.date(2026, 10, 6, 0, 0, tz: ba), createdAt: FX.date(2026, 10, 2, tz: ba)),
        ]
        let queryDays = (0..<42).map { cal.addDays($0, to: FX.date(2026, 9, 28, 12, tz: ba)) }
        func scheduleCase(_ name: String, _ entries: [ScheduleEntry]) -> [String: Any] {
            [
                "name": name, "timeZone": ba, "firstWeekday": 2, "entries": json(entries),
                "planned": queryDays.map { d in ["day": d.timeIntervalSince1970, "routineId": Schedule.plannedRoutine(on: d, entries: entries, calendar: cal).map { $0.uuidString as Any } ?? NSNull()] },
                "plannedDaysPerWeek": stride(from: 0, to: 42, by: 7).map { i in
                    ["date": queryDays[i].timeIntervalSince1970, "days": Schedule.plannedDays(inWeekOf: queryDays[i], entries: entries, calendar: cal).map(\.timeIntervalSince1970)]
                },
                "currentAssignments": json(Schedule.currentAssignments(asOf: queryDays[21], entries: entries, calendar: cal).mapKeys { String($0) }),
            ]
        }

        func session(_ n: Int, _ d: Date, sets: Int = 9, status: SessionStatus = .completed) -> SessionDigest {
            SessionDigest(id: FX.uuid(n), start: d, status: status, effectiveSets: sets)
        }
        let weekly = [
            session(1, FX.date(2026, 10, 5, 18, tz: ba)), session(2, FX.date(2026, 10, 7, 18, tz: ba)), session(3, FX.date(2026, 10, 9, 18, tz: ba)),
            session(4, FX.date(2026, 10, 12, 18, tz: ba)), session(5, FX.date(2026, 10, 13, 18, tz: ba)), session(6, FX.date(2026, 10, 17, 10, tz: ba)),
            session(7, FX.date(2026, 10, 19, 18, tz: ba)), session(8, FX.date(2026, 10, 21, 18, tz: ba), sets: 1),
            session(9, FX.date(2026, 10, 26, 18, tz: ba)), session(10, FX.date(2026, 10, 28, 18, tz: ba)), session(11, FX.date(2026, 10, 30, 18, tz: ba)),
            session(12, FX.date(2026, 11, 2, 18, tz: ba)), session(13, FX.date(2026, 11, 2, 20, tz: ba), status: .discarded),
        ]
        let complianceCases: [(String, [SessionDigest], [ScheduleEntry], Date)] = [
            ("weekly mode", weekly, monWedFri, FX.date(2026, 11, 3, 12, tz: ba)),
            ("weekly mode after change", weekly, changed, FX.date(2026, 11, 3, 12, tz: ba)),
            ("no plan", weekly, [], FX.date(2026, 11, 3, 12, tz: ba)),
            ("current week met", weekly, monWedFri, FX.date(2026, 10, 31, 12, tz: ba)),
        ]
        let gapDays = [FX.date(2026, 10, 1, tz: ba), FX.date(2026, 10, 3, tz: ba), FX.date(2026, 10, 5, tz: ba), FX.date(2026, 10, 9, tz: ba), FX.date(2026, 10, 10, tz: ba)].map { cal.day(of: $0) }
        let goalSessions = (0..<5).map { session($0, FX.date(2026, 10, 12 + $0, 18, tz: ba)) }

        return [
            "calendar": calendarCases,
            "schedule": [scheduleCase("mon-wed-fri", monWedFri), scheduleCase("changed with rest entry", changed),
                         scheduleCase("weekly plan snapshot", monWedFri + newPlan), scheduleCase("latest created wins", futureFirst)],
            "weeklyPlanEntries": [["assignments": ["2": routineA.uuidString, "5": routineB.uuidString], "validFrom": snapshotChange.timeIntervalSince1970,
                                   "createdAt": snapshotChange.timeIntervalSince1970, "timeZone": ba, "firstWeekday": 2, "firstId": 301, "entries": json(newPlan)]],
            "validSession": [(3, SessionStatus.completed, 3), (2, .completed, 3), (9, .active, 3), (9, .discarded, 3), (9, .paused, 3), (1, .completed, 0)].map {
                ["effectiveSets": $0.0, "status": $0.1.rawValue, "minSets": $0.2, "valid": SessionDigest(id: FX.uuid(1), start: FX.day(0), status: $0.1, effectiveSets: $0.0).isValid(minSets: $0.2)]
            },
            "compliance": complianceCases.map { c in
                let weeks = Streaks.weeklyCompliance(sessions: c.1, schedule: c.2, minSets: 3, now: c.3, calendar: cal)
                return ["name": c.0, "timeZone": ba, "firstWeekday": 2, "sessions": json(c.1), "schedule": json(c.2), "minSets": 3,
                        "now": c.3.timeIntervalSince1970, "weeks": json(weeks), "streak": json(Streaks.weeklyStreak(weeks))]
            },
            "trainingDays": [["timeZone": ba, "sessions": json(weekly + [session(20, FX.date(2026, 10, 1, 8, tz: ba)), session(21, FX.date(2026, 10, 1, 19, tz: ba))]),
                              "minSets": 3, "days": Streaks.trainingDays(weekly + [session(20, FX.date(2026, 10, 1, 8, tz: ba)), session(21, FX.date(2026, 10, 1, 19, tz: ba))], minSets: 3, calendar: cal).map(\.timeIntervalSince1970)]],
            "dayGap": [(2, FX.date(2026, 10, 12, tz: ba)), (2, FX.date(2026, 10, 13, tz: ba)), (1, FX.date(2026, 10, 10, tz: ba)), (4, FX.date(2026, 10, 14, tz: ba))].map { c in
                ["timeZone": ba, "days": gapDays.map(\.timeIntervalSince1970), "maxGapDays": c.0, "now": c.1.timeIntervalSince1970,
                 "result": json(Streaks.dayGapStreak(trainingDays: gapDays, maxGapDays: c.0, now: c.1, calendar: cal))]
            },
            "weeklyGoal": [(3, FX.date(2026, 10, 16, 20, tz: ba)), (7, FX.date(2026, 10, 14, 20, tz: ba)), (0, FX.date(2026, 10, 19, 20, tz: ba))].map { c in
                let r = Streaks.weeklyGoalProgress(sessions: goalSessions, goal: c.0, minSets: 3, now: c.1, calendar: cal)
                return ["timeZone": ba, "sessions": json(goalSessions), "goal": c.0, "minSets": 3, "now": c.1.timeIntervalSince1970,
                        "done": r.done, "goalUsed": r.goal, "fraction": r.fraction]
            },
        ]
    }

    // MARK: Parsing, validation, formatting

    static func parsing() -> [String: Any] {
        let weights = ["62,5", "62.5", " 62,50 ", "60", "0,25", ",5", "100.", "", "abc", "6,2,5", "1.000,5", "-5", "+5", "62 ,5", ".", "1e3",
                       "1.000", "62.500", "1,000", "0", "007", "62,5555", "123456789012", "12345678901", "１２", "62،5", "\t40\n",
                       "\u{FEFF}62,5", "62,5\u{85}", "\u{A0}62,5", "\u{2003}60\u{3000}", "62,5\u{200B}"]
        let ints = ["12", "12,5", "-3", "", " 8 ", "00012", "123456", "1e2", "٣"]
        let validations: [(Double?, Int?, Int?, Double?, Double?)] = [
            (-1, 5, nil, nil, nil), (600, 150, nil, nil, nil), (60, 10, nil, 2, 8), (60, 10, nil, 11, nil), (nil, nil, -1, nil, nil),
            (nil, nil, 4000, nil, nil), (500, 100, 3600, 0, 1), (.infinity, nil, nil, nil, nil), (nil, nil, nil, nil, 0.5), (nil, -2, nil, -1, 11),
        ]
        let numbers: [Double] = [62.5, 60, 0.25, 1234.5, 1000, 62.555, 62.554, 0.005, -17.5, 83.333, 2.675,
                                 -0.004, -0.0, -0.005, -0.006, 0.0049, 1234567.891, 999.995, 0.125, 0.135]
        let loads: [(Double, MeasurementType, LoadMode)] = [
            (62.5, .weightReps, .total), (24, .weightReps, .perSide), (0, .bodyweightReps, .total), (2.5, .bodyweightReps, .total),
            (-17.5, .bodyweightReps, .total), (0, .duration, .total), (5, .duration, .total), (1000, .weightReps, .total),
        ]
        return [
            "parse": weights.map { ["text": $0, "result": WeightParser.parse($0).map { $0 as Any } ?? NSNull()] },
            "parseInt": ints.map { ["text": $0, "result": WeightParser.parseInt($0).map { $0 as Any } ?? NSNull()] },
            "validate": validations.map { v in
                ["weight": v.0.map { $0.isFinite ? $0 as Any : "inf" } ?? NSNull(), "reps": v.1.map { $0 as Any } ?? NSNull(),
                 "seconds": v.2.map { $0 as Any } ?? NSNull(), "rir": v.3.map { $0 as Any } ?? NSNull(), "rpe": v.4.map { $0 as Any } ?? NSNull(),
                 "issues": SetValidator.validate(weight: v.0, reps: v.1, seconds: v.2, rir: v.3, rpe: v.4).map { issue -> [String: String] in
                     switch issue {
                     case let .error(m): return ["kind": "error", "message": m]
                     case let .warning(m): return ["kind": "warning", "message": m]
                     }
                 }]
            },
            "number": numbers.flatMap { n in ["es_AR", "en_US"].map { l in ["value": n, "locale": l, "text": GymFormat.number(n, locale: Locale(identifier: l))] } },
            "kg": numbers.map { ["value": $0, "text": GymFormat.kg($0)] },
            "load": loads.flatMap { l in ["es_AR", "en_US"].map { loc in
                ["value": l.0, "measurement": l.1.rawValue, "loadMode": l.2.rawValue, "locale": loc,
                 "text": GymFormat.load(l.0, measurement: l.1, loadMode: l.2, locale: Locale(identifier: loc))]
            } },
            "list": [[12, 12, 12], [], [8]].map { ["values": $0, "text": GymFormat.list($0)] },
            "labels": labels.map { l in
                ["text": l, "normalized": nn(ComparabilityContext(exerciseId: FX.benchId, variantLabel: l, loadMode: .total).normalized.variantLabel)]
            },
            "fold": foldTable(),
        ]
    }

    static let labels: [String] = [
        "  Polea  Gym A ", "Máquina", "MAQUINA", "e\u{301}", "inclinación", "inclinacio\u{301}n", "Straße", "Øster", "łódź",
        "đ ħ ŧ ı", "ǎ ạ ỳ", "a\u{FEFF}b", "a\u{85}b", "a\u{A0}b", "\u{2003}x\u{3000}", "", "   ", "a|b", "b|", "Ñandú", "İstanbul",
        "ﬁ", "Ⅻ", "ΣΑΣ", "Ελλάδα", "Москва", "x\u{200B}y", "TAB\tsep", "line\nbreak", "½", "²", "Ä̈",
        "а\u{483}", "\u{5D0}\u{5B7}", "\u{628}\u{64E}", "Ａ", "ﬀ", "x\u{20D7}",
    ]

    /// Swift folding of every scalar of the Latin, Greek and Cyrillic blocks that changes (single
    /// character, es_AR), so the Dart port reproduces it exactly.
    static func foldTable() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        let ranges: [ClosedRange<UInt32>] = [0x20...0x7E, 0xA0...0x24F, 0x250...0x2AF, 0x370...0x3FF, 0x400...0x52F, 0x1E00...0x1EFF, 0x2070...0x218F, 0xFB00...0xFB06]
        for range in ranges {
            for v in range {
                guard let scalar = Unicode.Scalar(v) else { continue }
                let c = String(Character(scalar))
                let folded = c.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_AR"))
                if folded != c { rows.append(["c": Int(v), "folded": folded]) }
            }
        }
        return rows
    }
}

extension Dictionary {
    func mapKeys<K: Hashable>(_ transform: (Key) -> K) -> [K: Value] {
        Dictionary<K, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
