/// Statistics for Progress, Home and Records (ports of StatsService.swift and StatsPeriod.swift,
/// sections 8.3–8.4, 9.4, 9.6). Every number comes from recorded sets (never invented).
library;

import 'package:gym_core/gym_core.dart';

import 'history_service.dart';
import 'records.dart';
import 'repository.dart';

// MARK: - Periods

enum StatsPeriodKind { week, last30Days, calendarMonth, last90Days, calendarYear, last12Months, custom }

/// Period filters of the Progress screen (section 9.4).
class StatsPeriod {
  final StatsPeriodKind kind;

  /// Only for `custom`.
  final DateInterval? customInterval;
  const StatsPeriod(this.kind) : customInterval = null;
  const StatsPeriod.custom(DateInterval interval) : kind = StatsPeriodKind.custom, customInterval = interval;

  String get label => switch (kind) {
    StatsPeriodKind.week => 'Semana',
    StatsPeriodKind.last30Days => 'Últimos 30 días',
    StatsPeriodKind.calendarMonth => 'Mes',
    StatsPeriodKind.last90Days => 'Últimos 90 días',
    StatsPeriodKind.calendarYear => 'Año',
    StatsPeriodKind.last12Months => 'Últimos 12 meses',
    StatsPeriodKind.custom => 'Personalizado',
  };

  /// Calendar periods (week, month, year) are still running until they end.
  bool get isCalendarPeriod =>
      kind == StatsPeriodKind.week || kind == StatsPeriodKind.calendarMonth || kind == StatsPeriodKind.calendarYear;

  /// Half-open interval [start, end) in the user's calendar.
  DateInterval interval(DateTime now, TrainingCalendar calendar) {
    final tomorrow = calendar.addDays(1, calendar.day(now));
    switch (kind) {
      case StatsPeriodKind.week:
        final start = calendar.weekStart(now);
        return DateInterval(start, calendar.addDays(7, start));
      case StatsPeriodKind.last30Days:
        return DateInterval(calendar.addDays(-30, tomorrow), tomorrow);
      case StatsPeriodKind.last90Days:
        return DateInterval(calendar.addDays(-90, tomorrow), tomorrow);
      case StatsPeriodKind.calendarMonth:
        final start = calendar.startOfMonth(now);
        return DateInterval(start, calendar.addMonths(1, start));
      case StatsPeriodKind.calendarYear:
        final start = calendar.startOfYear(now);
        return DateInterval(start, calendar.addMonths(12, start));
      case StatsPeriodKind.last12Months:
        return DateInterval(calendar.addMonths(-12, tomorrow), tomorrow);
      case StatsPeriodKind.custom:
        final i = customInterval!;
        return DateInterval(calendar.day(i.start), calendar.addDays(1, calendar.day(i.end)));
    }
  }

  /// The equivalent previous period.
  DateInterval previousInterval(DateTime now, TrainingCalendar calendar) {
    final current = interval(now, calendar);
    switch (kind) {
      case StatsPeriodKind.week:
        return DateInterval(calendar.addDays(-7, current.start), current.start);
      case StatsPeriodKind.calendarMonth:
        return DateInterval(calendar.addMonths(-1, current.start), current.start);
      case StatsPeriodKind.calendarYear:
        return DateInterval(calendar.addMonths(-12, current.start), current.start);
      case StatsPeriodKind.last12Months:
        return DateInterval(calendar.addMonths(-12, current.start), current.start);
      case StatsPeriodKind.last30Days:
      case StatsPeriodKind.last90Days:
      case StatsPeriodKind.custom:
        final days = calendar.daysBetween(current.start, current.end);
        return DateInterval(calendar.addDays(-days, current.start), current.start);
    }
  }

  /// Fair comparison: a running calendar period is compared day-for-day with the same elapsed span.
  ({DateInterval current, DateInterval previous}) comparableIntervals(DateTime now, TrainingCalendar calendar) {
    final current = interval(now, calendar);
    final previous = previousInterval(now, calendar);
    if (!isCalendarPeriod) return (current: current, previous: previous);
    final tomorrow = calendar.addDays(1, calendar.day(now));
    if (!tomorrow.isBefore(current.end)) return (current: current, previous: previous);
    final elapsed = calendar.daysBetween(current.start, tomorrow);
    final candidate = calendar.addDays(elapsed, previous.start);
    final previousEnd = candidate.isBefore(previous.end) ? candidate : previous.end;
    return (current: DateInterval(current.start, tomorrow), previous: DateInterval(previous.start, previousEnd));
  }
}

// MARK: - Results

class PeriodTotals {
  final int validSessions;
  final int effectiveSets;

  /// External load volume in kg (section 8.1). Not a proxy for strength or hypertrophy.
  final double volume;
  final int trainingDays;
  const PeriodTotals(this.validSessions, this.effectiveSets, this.volume, this.trainingDays);
}

class PeriodComparison {
  final PeriodTotals current;
  final PeriodTotals previous;

  /// True when a running calendar period is compared day-for-day with the same elapsed span.
  final bool isToDate;
  const PeriodComparison(this.current, this.previous, this.isToDate);
}

/// A group of mutually comparable contexts of one exercise (same machine/variant/load mode, or
/// linked by the user). Records and charts are computed per class (section 8.1).
class ContextClass {
  final ComparabilityContext representative;

  /// Identity keys of the member contexts (normalized).
  final Set<String> contexts;

  /// Sort keys of the member contexts (Swift `contexts.map(\.sortKey)`), for display/ordering.
  final Set<String> contextSortKeys;

  /// "estándar" or the machine/variant labels.
  final String label;
  DateTime lastUsed;
  ContextClass(this.representative, this.contexts, this.contextSortKeys, this.label, this.lastUsed);

  String get id => representative.sortKey;
}

/// One session of one exercise, as a chart point.
class ExercisePoint {
  final String exerciseLogId;
  final DateTime date;
  final MeasurementType measurement;
  final LoadMode loadMode;

  /// Working load (external kg; body weight: net added load, negative = assistance).
  final double workingLoad;

  /// Total reps, or total seconds for duration exercises.
  final int totalAmount;
  final int bestSetAmount;

  /// Estimated, capped by the user's rep limit; null when no set qualifies.
  final double? estimatedOneRepMax;
  final double volume;
  final int effectiveSets;
  final bool isAtypical;

  const ExercisePoint({
    required this.exerciseLogId,
    required this.date,
    required this.measurement,
    required this.loadMode,
    required this.workingLoad,
    required this.totalAmount,
    required this.bestSetAmount,
    required this.estimatedOneRepMax,
    required this.volume,
    required this.effectiveSets,
    required this.isAtypical,
  });
}

class RecentRecord {
  final String exerciseId;
  final String exerciseName;

  /// Context the record belongs to ("estándar", machine, variant).
  final String contextLabel;
  final PersonalRecord record;
  const RecentRecord(this.exerciseId, this.exerciseName, this.contextLabel, this.record);

  String get id => '$exerciseId|$contextLabel|${record.kind.name}|${record.exerciseLogId}|${record.setIndex ?? -1}';
}

class GoalProgress {
  final Goal goal;

  /// Best value achieved so far for the goal's metric (null = no data yet).
  final double? current;
  final double fraction;
  final bool achieved;

  /// When the goal was first reached (date of the record that reached it).
  final DateTime? achievedOn;
  const GoalProgress(this.goal, this.current, this.fraction, this.achieved, this.achievedOn);
}

class WeeklySets {
  final DateTime weekStart;
  final int directSets;
  final double indirectSets;
  const WeeklySets(this.weekStart, this.directSets, this.indirectSets);
}

// MARK: - Service

class StatsService {
  final GymRepository repository;
  final String timeZone;
  const StatsService(this.repository, {required this.timeZone});

  TrainingCalendar get calendar =>
      TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday);

  HistoryService get _history => HistoryService(repository);

  PeriodTotals totals(DateInterval interval, {String? routineId}) {
    final settings = repository.settings();
    final cal = calendar;
    var effective = 0, valid = 0;
    var volume = 0.0;
    final days = <int>{};
    for (final session in repository.sessions()) {
      if (session.status != SessionStatus.completed || !interval.containsHalfOpen(session.startedAt)) continue;
      if (routineId != null && session.routineId != routineId) continue;
      var sessionSets = 0;
      for (final log in repository.exerciseLogsOfSession(session.id)) {
        final v = Volume.of(_history.performanceOf(log, session), bodyweight: settings.bodyweightKg);
        sessionSets += v.effectiveSets;
        volume += v.total;
      }
      effective += sessionSets;
      if (sessionSets >= settings.minSetsForValidSession) {
        valid++;
        days.add(cal.day(session.startedAt).microsecondsSinceEpoch);
      }
    }
    return PeriodTotals(valid, effective, LoadMath.normalized(volume), days.length);
  }

  /// Current vs. equivalent previous period. Running calendar periods are compared to date.
  PeriodComparison comparison(StatsPeriod period, {required DateTime now, String? routineId}) {
    final cal = calendar;
    final intervals = period.comparableIntervals(now, cal);
    final full = period.interval(now, cal);
    return PeriodComparison(
      totals(intervals.current, routineId: routineId),
      totals(intervals.previous, routineId: routineId),
      intervals.current.start.compareTo(full.start) != 0 || intervals.current.end.compareTo(full.end) != 0,
    );
  }

  /// Comparable context groups of an exercise (links respected), most recently used first.
  List<ContextClass> contextClasses(String exerciseId) {
    final links = repository.comparabilityLinks();
    final resolver = ComparabilityResolver(links);
    final classes = <ContextClass>[];
    for (final entry in _history.exerciseHistory(exerciseId)) {
      // newest first
      final key = entry.log.context.identityKey;
      final existing = classes.where((c) => c.contexts.contains(key));
      if (existing.isNotEmpty) {
        final c = existing.first;
        if (entry.session.startedAt.isAfter(c.lastUsed)) c.lastUsed = entry.session.startedAt;
        continue;
      }
      final members = resolver.equivalenceClass(entry.log.context);
      final labels = [entry.log.equipmentLabel, entry.log.variantLabel].whereType<String>().toList();
      classes.add(
        ContextClass(
          entry.log.context,
          members,
          _sortKeysOf(entry.log.context, links),
          labels.isEmpty ? 'estándar' : labels.join(' · '),
          entry.session.startedAt,
        ),
      );
    }
    return classes;
  }

  /// Sort keys of the equivalence class (same traversal as the resolver).
  static Set<String> _sortKeysOf(ComparabilityContext context, List<ComparabilityLink> links) {
    final start = context.normalized;
    final visited = <String>{start.identityKey};
    final keys = <String>{start.sortKey};
    final frontier = [start];
    final edges = links.map((l) => (l.a.normalized, l.b.normalized)).toList();
    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();
      for (final (a, b) in edges) {
        final other = a == current ? b : (b == current ? a : null);
        if (other != null && visited.add(other.identityKey)) {
          keys.add(other.sortKey);
          frontier.add(other);
        }
      }
    }
    return keys;
  }

  /// The class of the context the user trains this exercise in now (last used).
  ContextClass? currentContextClass(String exerciseId) {
    final classes = contextClasses(exerciseId);
    return classes.isEmpty ? null : classes.first;
  }

  List<ExerciseHistoryEntry> _entries(String exerciseId, ContextClass? contextClass) {
    final all = _history.exerciseHistory(exerciseId);
    if (contextClass == null) return all;
    return all.where((e) => contextClass.contexts.contains(e.log.context.identityKey)).toList();
  }

  /// One point per completed session of the exercise in one comparability class (default: the
  /// current one), inside `interval`, oldest first. Different machines/variants are never joined.
  List<ExercisePoint> exerciseSeries(
    String exerciseId, {
    DateInterval? interval,
    ContextClass? contextClass,
    String? routineId,
  }) {
    final settings = repository.settings();
    final selected = contextClass ?? currentContextClass(exerciseId);
    final points = <ExercisePoint>[];
    final entries = _entries(exerciseId, selected)
        .where(
          (e) =>
              (interval?.containsHalfOpen(e.session.startedAt) ?? true) &&
              (routineId == null || e.session.routineId == routineId),
        )
        .toList()
        .reversed;
    for (final entry in entries) {
      final perf = entry.performance;
      if (perf.progressionSets.isEmpty) continue;
      final summary = HistoryAnalyzer.summary(perf);
      final volume = Volume.of(perf, bodyweight: settings.bodyweightKg);
      final amounts = summary.amounts;
      final best = OneRepMax.best(perf, settings.oneRepMax);
      points.add(
        ExercisePoint(
          exerciseLogId: entry.log.id,
          date: entry.session.startedAt,
          measurement: perf.measurement,
          loadMode: perf.context.loadMode,
          workingLoad: summary.workingLoad,
          totalAmount: amounts.fold(0, (a, b) => a + b),
          bestSetAmount: amounts.isEmpty ? 0 : amounts.reduce((a, b) => a > b ? a : b),
          estimatedOneRepMax: best == null ? null : LoadMath.normalized(best),
          volume: volume.total,
          effectiveSets: volume.effectiveSets,
          isAtypical: perf.isAtypical,
        ),
      );
    }
    return points;
  }

  /// Direct and indirect sets per muscle in the interval (reported separately).
  List<MuscleSetVolume> muscleVolume(DateInterval interval, {String? routineId}) {
    final settings = repository.settings();
    final work = _history.muscleWork(interval, routineId: routineId);
    return MuscleVolume.compute(work, calendar, indirectFactor: settings.indirectSetFactor);
  }

  /// Weekly direct and indirect sets for one muscle over the last `weeks` weeks (oldest first).
  List<WeeklySets> weeklyDirectSets(MuscleGroup muscle, {required int weeks, required DateTime now}) {
    final cal = calendar;
    final currentStart = cal.weekStart(now);
    final n = weeks < 1 ? 1 : weeks;
    return [
      for (var back = n - 1; back >= 0; back--)
        () {
          final start = cal.addDays(-7 * back, currentStart);
          final rows = muscleVolume(DateInterval(start, cal.addDays(7, start))).where((v) => v.muscle == muscle);
          final v = rows.isEmpty ? null : rows.first;
          return WeeklySets(start, v?.directSets ?? 0, v?.indirectSets ?? 0);
        }(),
    ];
  }

  /// Records of one comparability class (default: the current one). Different machines/variants
  /// are never mixed.
  RecordSummary records(String exerciseId, {ContextClass? contextClass}) {
    final selected = contextClass ?? currentContextClass(exerciseId);
    final settings = repository.settings();
    return PersonalRecords.compute(
      _entries(exerciseId, selected).map((e) => e.performance).toList(),
      oneRepMax: settings.oneRepMax,
      bodyweight: settings.bodyweightKg,
    );
  }

  /// Records *broken* within the last `days` days, newest first: one entry per (exercise, context,
  /// kind, session) with the best value of that session.
  List<RecentRecord> recentRecords({required int days, required DateTime now, int limit = 5}) {
    final cal = calendar;
    final since = cal.addDays(-days, cal.day(now));
    final result = <RecentRecord>[];
    for (final exercise in repository.exercises()) {
      if (!repository.hasExerciseHistory(exercise.id)) continue;
      for (final contextClass in contextClasses(exercise.id)) {
        final summary = records(exercise.id, contextClass: contextClass);
        final bestPerSessionKind = <String, PersonalRecord>{};
        // Session (log) where each kind was first recorded: values from that session are the
        // starting point, not records broken.
        final firstLogOfKind = <RecordKind, String>{};
        for (final record in summary.history) {
          final first = firstLogOfKind.putIfAbsent(record.kind, () => record.exerciseLogId);
          if (record.exerciseLogId == first || record.date.isBefore(since) || record.date.isAfter(now)) continue;
          final key = '${record.kind.name}|${record.exerciseLogId}';
          final existing = bestPerSessionKind[key];
          if (existing != null && existing.value >= record.value) continue;
          bestPerSessionKind[key] = record;
        }
        result.addAll(
          bestPerSessionKind.values.map((r) => RecentRecord(exercise.id, exercise.name, contextClass.label, r)),
        );
      }
    }
    final sorted = stableSorted(result, (RecentRecord a, RecentRecord b) {
      final c = b.record.date.compareTo(a.record.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return sorted.take(limit).toList();
  }

  /// Progress of every goal, measured in the exercise's current comparability class.
  List<GoalProgress> goalProgress({required DateTime now}) => repository.goals().map((goal) {
    final summary = records(goal.exerciseId);
    double? current;
    DateTime? reachedOn;
    DateTime? firstReached(RecordKind kind) {
      for (final r in summary.history) {
        if (r.kind == kind && r.value >= goal.value) return r.date;
      }
      return null;
    }

    switch (goal.metric) {
      case GoalMetric.weight:
        current = summary.maxWeight?.value;
        reachedOn = firstReached(RecordKind.maxWeight);
      case GoalMetric.estimatedOneRepMax:
        current = summary.bestEstimatedOneRepMax?.value;
        reachedOn = firstReached(RecordKind.bestEstimatedOneRepMax);
      case GoalMetric.sessionVolume:
        current = summary.maxSessionVolume?.value;
        reachedOn = firstReached(RecordKind.maxSessionVolume);
      case GoalMetric.repsAtWeight:
        final w = goal.weight;
        final eligible = w == null
            ? const <PersonalRecord>[]
            : summary.maxRepsAtWeight.where((r) => (r.weight ?? 0) >= w - LoadMath.resolution).toList();
        current = eligible.isEmpty ? null : eligible.map((r) => r.value).reduce((a, b) => a > b ? a : b);
        final reached = eligible.where((r) => r.value >= goal.value).map((r) => r.date).toList();
        reachedOn = reached.isEmpty ? null : reached.reduce((a, b) => b.isBefore(a) ? b : a);
    }
    final achieved = (current ?? 0) >= goal.value && goal.value > 0;
    final fraction = current == null
        ? 0.0
        : (goal.value > 0 ? (current / goal.value < 1 ? current / goal.value : 1.0) : 0.0);
    return GoalProgress(goal, current, fraction, achieved, achieved ? reachedOn : null);
  }).toList();

  /// Marks reached goals as achieved, dated when the record reached them. Returns the new ones.
  List<Goal> refreshGoals({required DateTime now}) {
    return repository.transaction(() {
      final achieved = <Goal>[];
      for (final progress in goalProgress(now: now)) {
        if (!progress.achieved || progress.goal.status != GoalStatus.active) continue;
        final g = progress.goal
          ..status = GoalStatus.achieved
          ..achievedAt = progress.achievedOn ?? now.toUtc();
        repository.upsertGoal(g);
        achieved.add(g);
      }
      return achieved;
    });
  }
}
