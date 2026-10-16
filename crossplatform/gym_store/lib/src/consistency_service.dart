/// Calendar, schedule and consistency (port of ConsistencyService.swift, section 8.5).
library;

import 'package:gym_core/gym_core.dart';

import 'history_service.dart';
import 'records.dart';
import 'repository.dart';

enum CalendarDayStatus {
  /// At least one valid (completed) session that day.
  completed,

  /// Planned, in the future or today without a session yet.
  planned,

  /// Planned, in the past, and no valid session that day.
  missed,

  /// Not planned (scheduled rest or no plan) and no session.
  rest,
}

class CalendarDay {
  final DateTime date;
  final CalendarDayStatus status;
  final String? plannedRoutineId;
  final String? plannedRoutineName;
  final List<String> sessionIds;
  final bool isToday;
  const CalendarDay(
    this.date,
    this.status,
    this.plannedRoutineId,
    this.plannedRoutineName,
    this.sessionIds,
    this.isToday,
  );
}

class WeekSummary {
  final DateTime weekStart;
  final int planned;
  final int validSessions;
  final int weeklyGoal;

  /// min(1, valid / goal): the UI celebrates 100 % without pushing to train more.
  final double goalFraction;
  final bool goalMet;
  const WeekSummary(this.weekStart, this.planned, this.validSessions, this.weeklyGoal, this.goalFraction, this.goalMet);
}

class StreakSummary {
  final StreakResult result;

  /// User-facing definition of the mode in use (section 8.5).
  final String definition;
  const StreakSummary(this.result, this.definition);
}

class ConsistencyService {
  final GymRepository repository;
  final String timeZone;
  const ConsistencyService(this.repository, {required this.timeZone});

  TrainingCalendar get calendar =>
      TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday);

  int get _minSets => repository.settings().minSetsForValidSession;

  // MARK: Schedule

  /// Replaces the weekly plan from `from` onwards (append-only: past days keep their plan).
  /// `assignments`: weekday (1 = Sunday … 7 = Saturday) → routine. Missing weekdays = rest.
  void setWeeklyPlan(Map<int, String> assignments, {required DateTime from, required DateTime now}) {
    repository.transaction(() {
      final cal = calendar;
      // Never earlier than today: a plan change can't rewrite planned/missed days in the past.
      final a = cal.day(from), b = cal.day(now);
      final start = a.isAfter(b) ? a : b;
      for (final entry in Schedule.weeklyPlanEntries(assignments, start, now.toUtc(), cal, newUuid)) {
        repository.insertScheduleEntry(entry);
      }
    });
  }

  /// Plan in force on `day` (weekday → routine).
  Map<int, String> plan(DateTime day) => Schedule.currentAssignments(day, repository.scheduleEntries(), calendar);

  String? plannedRoutine(DateTime day) => Schedule.plannedRoutine(day, repository.scheduleEntries(), calendar);

  /// Next planned workout from today: skips today when today's planned routine was already done
  /// (or today is a rest day). Looks up to two weeks ahead; null without a plan.
  ({DateTime date, String routineId})? nextPlannedWorkout(DateTime now) {
    final entries = repository.scheduleEntries();
    if (entries.isEmpty) return null;
    final cal = calendar;
    final today = cal.day(now);
    final doneToday = repository.sessions().any(
      (s) => s.status == SessionStatus.completed && cal.day(s.startedAt).compareTo(today) == 0,
    );
    for (var offset = 0; offset < 14; offset++) {
      final day = cal.addDays(offset, today);
      if (offset == 0 && doneToday) continue;
      final routine = Schedule.plannedRoutine(day, entries, cal);
      if (routine != null) return (date: day, routineId: routine);
    }
    return null;
  }

  // MARK: Calendar

  List<CalendarDay> month(DateTime date, {required DateTime now}) => _days(calendar.daysInMonth(date), now);

  List<CalendarDay> week(DateTime date, {required DateTime now}) => _days(calendar.daysOfWeek(date), now);

  List<CalendarDay> _days(List<DateTime> dayStarts, DateTime now) {
    final cal = calendar;
    final entries = repository.scheduleEntries();
    final digests = HistoryService(repository).sessionDigests();
    final routineNames = <String, String>{};
    for (final r in repository.routines()) {
      routineNames.putIfAbsent(r.id, () => r.name);
    }
    final validByDay = <int, List<String>>{};
    for (final d in digests) {
      if (d.isValid(_minSets)) validByDay.putIfAbsent(cal.day(d.start).microsecondsSinceEpoch, () => []).add(d.id);
    }
    final today = cal.day(now);
    return dayStarts.map((day) {
      final planned = Schedule.plannedRoutine(day, entries, cal);
      final sessions = validByDay[day.microsecondsSinceEpoch] ?? const <String>[];
      final CalendarDayStatus status;
      if (sessions.isNotEmpty) {
        status = CalendarDayStatus.completed;
      } else if (planned != null) {
        status = day.isBefore(today) ? CalendarDayStatus.missed : CalendarDayStatus.planned;
      } else {
        status = CalendarDayStatus.rest;
      }
      return CalendarDay(
        day,
        status,
        planned,
        planned == null ? null : routineNames[planned],
        List.of(sessions),
        day.compareTo(today) == 0,
      );
    }).toList();
  }

  // MARK: Consistency

  WeekSummary weekSummary(DateTime now) {
    final settings = repository.settings();
    final cal = calendar;
    final digests = HistoryService(repository).sessionDigests();
    final progress = Streaks.weeklyGoalProgress(digests, settings.weeklyGoal, _minSets, now, cal);
    final planned = Schedule.plannedDays(now, repository.scheduleEntries(), cal).length;
    return WeekSummary(
      cal.weekStart(now),
      planned,
      progress.done,
      progress.goal,
      progress.fraction,
      progress.done >= progress.goal,
    );
  }

  StreakSummary streak(DateTime now) {
    final settings = repository.settings();
    final cal = calendar;
    final digests = HistoryService(repository).sessionDigests();
    final minSets = _minSets;
    switch (settings.streakMode) {
      case StreakMode.weeklyPlan:
        final schedule = repository.scheduleEntries();
        final weeks = Streaks.weeklyCompliance(
          sessions: digests,
          schedule: schedule,
          minSets: minSets,
          now: now,
          calendar: cal,
        );
        return StreakSummary(
          Streaks.weeklyStreak(weeks),
          'Semanas seguidas cumpliendo el plan: entrenamientos válidos (≥ $minSets series efectivas) ≥ días planificados. Los descansos programados no cuentan como fallo y la semana en curso no corta la racha.${schedule.isEmpty ? ' Necesita un plan semanal: definilo en Calendario o cambiá el modo de racha en Perfil.' : ''}',
        );
      case StreakMode.dayGap:
        final days = Streaks.trainingDays(digests, minSets, cal);
        return StreakSummary(
          Streaks.dayGapStreak(days, settings.maxGapDays, now, cal),
          'Días de entrenamiento seguidos, con no más de ${settings.maxGapDays} días entre un entrenamiento válido '
          '(≥ $minSets series efectivas) y el siguiente.',
        );
    }
  }
}
