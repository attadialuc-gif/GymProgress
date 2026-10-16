/// Ports of TrainingCalendar.swift, Schedule.swift and Streaks.swift.
///
/// Instants are UTC `DateTime`s; days and weeks are derived in the user's IANA time zone (package
/// `timezone`, embedded tz database), reproducing Foundation's gregorian `Calendar`:
/// - wall-clock times that do not exist (DST gap) resolve with the offset in force before the gap
///   (02:30 → 03:30), like Foundation;
/// - repeated wall-clock times (DST overlap) resolve to the first occurrence;
/// - adding days keeps the wall-clock time; day differences are counted like
///   `dateComponents([.day], from:to:)`.
library;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'enums.dart';
import 'json_util.dart';

bool _tzReady = false;

tz.Location _location(String name) {
  if (!_tzReady) {
    tzdata.initializeTimeZones();
    _tzReady = true;
  }
  return name == 'UTC' ? tz.UTC : tz.getLocation(name);
}

/// Local wall-clock components of an instant.
class LocalDateTime {
  final int year, month, day, hour, minute, second, microsecond;
  const LocalDateTime(this.year, this.month, this.day, this.hour, this.minute, this.second, this.microsecond);

  /// 1 = Sunday … 7 = Saturday (Foundation convention).
  int get weekday => DateTime.utc(year, month, day).weekday % 7 + 1;
}

class TrainingCalendar {
  final String timeZone;

  /// 1 = Sunday … 7 = Saturday. Default Monday (2).
  final int firstWeekday;
  final tz.Location _loc;

  TrainingCalendar({this.timeZone = 'UTC', int firstWeekday = 2})
    : firstWeekday = firstWeekday < 1 ? 1 : (firstWeekday > 7 ? 7 : firstWeekday),
      _loc = _location(timeZone);

  int _offsetUs(int utcUs) => _loc.timeZone(_floorDiv(utcUs, 1000)).offset * 1000;

  static int _floorDiv(int a, int b) => (a / b).floor();

  LocalDateTime local(DateTime instant) {
    final us = instant.microsecondsSinceEpoch;
    final l = DateTime.fromMicrosecondsSinceEpoch(us + _offsetUs(us), isUtc: true);
    return LocalDateTime(l.year, l.month, l.day, l.hour, l.minute, l.second, l.millisecond * 1000 + l.microsecond);
  }

  /// Instant of a local wall-clock time (components may overflow, like `DateTime.utc`).
  DateTime instant(int year, int month, int day, [int hour = 0, int minute = 0, int second = 0, int microsecond = 0]) {
    final naive = DateTime.utc(year, month, day, hour, minute, second, 0, microsecond).microsecondsSinceEpoch;
    const dayUs = 86400 * 1000000;
    final before = _offsetUs(naive - dayUs);
    final candidates = <int>{before, _offsetUs(naive), _offsetUs(naive + dayUs)};
    int? best;
    for (final o in candidates) {
      final utc = naive - o;
      if (_offsetUs(utc) == o && (best == null || utc < best)) best = utc;
    }
    // DST gap: interpret with the offset in force before the transition.
    return DateTime.fromMicrosecondsSinceEpoch(best ?? naive - before, isUtc: true);
  }

  DateTime day(DateTime date) {
    final l = local(date);
    return instant(l.year, l.month, l.day);
  }

  /// 1 = Sunday … 7 = Saturday.
  int weekday(DateTime date) => local(date).weekday;

  DateTime weekStart(DateTime date) {
    final d = day(date);
    final offset = (weekday(d) - firstWeekday + 7) % 7;
    return addDays(-offset, d);
  }

  /// Adds calendar days keeping the wall-clock time (DST-safe).
  DateTime addDays(int days, DateTime date) {
    final l = local(date);
    return instant(l.year, l.month, l.day + days, l.hour, l.minute, l.second, l.microsecond);
  }

  /// Whole calendar days from `a` to `b` (can be negative).
  int daysBetween(DateTime a, DateTime b) {
    final start = day(a), end = day(b);
    final ls = local(start), le = local(end);
    var n = DateTime.utc(le.year, le.month, le.day).difference(DateTime.utc(ls.year, ls.month, ls.day)).inDays;
    // Foundation counts complete days of wall-clock arithmetic.
    if (n > 0 && addDays(n, start).isAfter(end)) n -= 1;
    if (n < 0 && addDays(n, start).isBefore(end)) n += 1;
    return n;
  }

  List<DateTime> daysOfWeek(DateTime date) {
    final start = weekStart(date);
    return [for (var i = 0; i < 7; i++) addDays(i, start)];
  }

  DateTime startOfMonth(DateTime date) {
    final l = local(date);
    return instant(l.year, l.month, 1);
  }

  /// January 1st, 00:00 of the year of `date` (Foundation `date(from: [.year])`).
  DateTime startOfYear(DateTime date) => instant(local(date).year, 1, 1);

  /// Foundation `date(byAdding: .month)`: the day is clamped to the target month's length and the
  /// wall-clock time is kept.
  DateTime addMonths(int months, DateTime date) {
    final l = local(date);
    final total = l.year * 12 + (l.month - 1) + months;
    final year = (total / 12).floor();
    final month = total - year * 12 + 1;
    final daysInTarget = DateTime.utc(year, month + 1, 0).day;
    final day = l.day < daysInTarget ? l.day : daysInTarget;
    return instant(year, month, day, l.hour, l.minute, l.second, l.microsecond);
  }

  List<DateTime> daysInMonth(DateTime date) {
    final start = startOfMonth(date);
    final l = local(start);
    final count = DateTime.utc(l.year, l.month + 1, 0).day;
    return [for (var i = 0; i < count; i++) addDays(i, start)];
  }
}

// MARK: - Schedule

class ScheduleEntry {
  final String id;

  /// 1 = Sunday … 7 = Saturday.
  final int weekday;
  final String? routineId;
  final DateTime validFrom;
  final DateTime? validTo;
  final DateTime createdAt;

  const ScheduleEntry({
    required this.id,
    required this.weekday,
    this.routineId,
    required this.validFrom,
    this.validTo,
    required this.createdAt,
  });

  factory ScheduleEntry.fromJson(Json j) => ScheduleEntry(
    id: uuidFromJson(j['id']),
    weekday: toInt(j['weekday']),
    routineId: optUuid(j['routineId']),
    validFrom: dateFromJson(j['validFrom']),
    validTo: optDate(j['validTo']),
    createdAt: dateFromJson(j['createdAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'weekday': weekday,
      'validFrom': dateToJson(validFrom),
      'createdAt': dateToJson(createdAt),
    };
    putOpt(j, 'routineId', routineId);
    putOpt(j, 'validTo', validTo == null ? null : dateToJson(validTo!));
    return j;
  }
}

class Schedule {
  /// Routine planned for `day`, or null for a rest / unplanned day. Latest created entry wins
  /// (ties: later validFrom, then id).
  static String? plannedRoutine(DateTime day, List<ScheduleEntry> entries, TrainingCalendar calendar) {
    final dayStart = calendar.day(day);
    final weekday = calendar.weekday(dayStart);
    ScheduleEntry? winner;
    for (final e in entries) {
      if (e.weekday != weekday) continue;
      if (calendar.day(e.validFrom).isAfter(dayStart)) continue;
      if (e.validTo != null && !dayStart.isBefore(calendar.day(e.validTo!))) continue;
      if (winner == null || _before(winner, e)) winner = e;
    }
    return winner?.routineId;
  }

  static bool _before(ScheduleEntry a, ScheduleEntry b) {
    if (a.createdAt.compareTo(b.createdAt) != 0) return a.createdAt.isBefore(b.createdAt);
    if (a.validFrom.compareTo(b.validFrom) != 0) return a.validFrom.isBefore(b.validFrom);
    return a.id.compareTo(b.id) < 0;
  }

  static bool isPlanned(DateTime day, List<ScheduleEntry> entries, TrainingCalendar calendar) =>
      plannedRoutine(day, entries, calendar) != null;

  static List<DateTime> plannedDays(DateTime date, List<ScheduleEntry> entries, TrainingCalendar calendar) =>
      calendar.daysOfWeek(date).where((d) => isPlanned(d, entries, calendar)).toList();

  /// One entry per weekday (1…7) from `validFrom`, null routine = explicit rest day.
  static List<ScheduleEntry> weeklyPlanEntries(
    Map<int, String> assignments,
    DateTime validFrom,
    DateTime createdAt,
    TrainingCalendar calendar,
    String Function() makeId,
  ) {
    final start = calendar.day(validFrom);
    return [
      for (var weekday = 1; weekday <= 7; weekday++)
        ScheduleEntry(
          id: makeId(),
          weekday: weekday,
          routineId: assignments[weekday],
          validFrom: start,
          createdAt: createdAt,
        ),
    ];
  }

  static Map<int, String> currentAssignments(DateTime day, List<ScheduleEntry> entries, TrainingCalendar calendar) {
    final result = <int, String>{};
    for (var offset = 0; offset < 7; offset++) {
      final d = calendar.addDays(offset, calendar.day(day));
      final routine = plannedRoutine(d, entries, calendar);
      if (routine != null) result[calendar.weekday(d)] = routine;
    }
    return result;
  }
}

// MARK: - Streaks

class SessionDigest {
  final String id;
  final DateTime start;
  final SessionStatus status;
  final int effectiveSets;
  final String? routineId;

  const SessionDigest({
    required this.id,
    required this.start,
    required this.status,
    required this.effectiveSets,
    this.routineId,
  });

  bool isValid(int minSets) => status == SessionStatus.completed && effectiveSets >= (minSets < 1 ? 1 : minSets);

  factory SessionDigest.fromJson(Json j) => SessionDigest(
    id: uuidFromJson(j['id']),
    start: dateFromJson(j['start']),
    status: enumFromName(SessionStatus.values, j['status']),
    effectiveSets: toInt(j['effectiveSets']),
    routineId: optUuid(j['routineId']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'start': dateToJson(start),
      'status': status.name,
      'effectiveSets': effectiveSets,
    };
    putOpt(j, 'routineId', routineId);
    return j;
  }
}

enum StreakMode { weeklyPlan, dayGap }

enum WeekStatus { met, missed, noPlan, inProgress }

class WeekCompliance {
  final DateTime weekStart;
  final int planned;
  final int valid;
  final WeekStatus status;
  const WeekCompliance(this.weekStart, this.planned, this.valid, this.status);

  Json toJson() => {'weekStart': dateToJson(weekStart), 'planned': planned, 'valid': valid, 'status': status.name};
}

class StreakResult {
  final StreakMode mode;
  final int current;
  final int best;
  const StreakResult(this.mode, this.current, this.best);

  Json toJson() => {'mode': mode.name, 'current': current, 'best': best};
}

class WeeklyGoalProgress {
  final int done;
  final int goal;
  final double fraction;
  const WeeklyGoalProgress(this.done, this.goal, this.fraction);
}

class Streaks {
  /// Day starts of valid sessions (one per day), ascending.
  static List<DateTime> trainingDays(List<SessionDigest> sessions, int minSets, TrainingCalendar calendar) {
    final days = <int>{};
    for (final s in sessions) {
      if (s.isValid(minSets)) days.add(calendar.day(s.start).microsecondsSinceEpoch);
    }
    final sorted = days.toList()..sort();
    return sorted.map((us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true)).toList();
  }

  static List<WeekCompliance> weeklyCompliance({
    required List<SessionDigest> sessions,
    required List<ScheduleEntry> schedule,
    required int minSets,
    required DateTime now,
    required TrainingCalendar calendar,
  }) {
    final valid = sessions.where((s) => s.isValid(minSets)).toList();
    final firstDates = [...valid.map((s) => s.start), ...schedule.map((e) => e.validFrom)];
    if (firstDates.isEmpty) return [];
    final first = firstDates.reduce((a, b) => b.isBefore(a) ? b : a);

    final currentWeek = calendar.weekStart(now);
    var week = calendar.weekStart(first);
    final result = <WeekCompliance>[];
    var guardCount = 0;
    while (!week.isAfter(currentWeek) && guardCount < 5000) {
      guardCount++;
      final next = calendar.addDays(7, week);
      final planned = Schedule.plannedDays(week, schedule, calendar).length;
      final count = valid.where((s) => !s.start.isBefore(week) && s.start.isBefore(next)).length;
      final WeekStatus status;
      if (planned == 0) {
        status = WeekStatus.noPlan;
      } else if (count >= planned) {
        status = WeekStatus.met;
      } else if (week.compareTo(currentWeek) == 0) {
        status = WeekStatus.inProgress;
      } else {
        status = WeekStatus.missed;
      }
      result.add(WeekCompliance(week, planned, count, status));
      week = next;
    }
    return result;
  }

  static StreakResult weeklyStreak(List<WeekCompliance> weeks) {
    var best = 0, run = 0;
    for (final w in weeks) {
      switch (w.status) {
        case WeekStatus.met:
          run++;
          if (run > best) best = run;
        case WeekStatus.missed:
          run = 0;
        case WeekStatus.noPlan:
        case WeekStatus.inProgress:
          break;
      }
    }
    return StreakResult(StreakMode.weeklyPlan, run, best);
  }

  static StreakResult dayGapStreak(
    List<DateTime> trainingDays,
    int maxGapDays,
    DateTime now,
    TrainingCalendar calendar,
  ) {
    final k = maxGapDays < 1 ? 1 : maxGapDays;
    var best = 0, run = 0;
    DateTime? previous;
    for (final day in trainingDays) {
      if (previous != null && calendar.daysBetween(previous, day) <= k) {
        run++;
      } else {
        run = 1;
      }
      if (run > best) best = run;
      previous = day;
    }
    final alive = previous != null && calendar.daysBetween(previous, now) <= k;
    return StreakResult(StreakMode.dayGap, alive ? run : 0, best);
  }

  static WeeklyGoalProgress weeklyGoalProgress(
    List<SessionDigest> sessions,
    int goal,
    int minSets,
    DateTime now,
    TrainingCalendar calendar,
  ) {
    final start = calendar.weekStart(now);
    final end = calendar.addDays(7, start);
    final done = sessions.where((s) => s.isValid(minSets) && !s.start.isBefore(start) && s.start.isBefore(end)).length;
    final g = goal < 1 ? 1 : goal;
    final f = done / g;
    return WeeklyGoalProgress(done, g, f < 1 ? f : 1.0);
  }
}
