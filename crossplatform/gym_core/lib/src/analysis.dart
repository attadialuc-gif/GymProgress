/// Ports of OneRepMax.swift, Trend.swift and HistoryAnalyzer.swift.
library;

import 'dart:math' as math;

import 'enums.dart';
import 'json_util.dart';
import 'load_math.dart';
import 'models.dart';
import 'recommendation.dart';

// MARK: - 1RM

enum OneRepMaxFormula { epley, brzycki }

class OneRepMaxSettings {
  final OneRepMaxFormula formula;
  final int maxReps;
  const OneRepMaxSettings({this.formula = OneRepMaxFormula.epley, this.maxReps = 10});

  static const standard = OneRepMaxSettings();

  factory OneRepMaxSettings.fromJson(Json j) =>
      OneRepMaxSettings(formula: enumFromName(OneRepMaxFormula.values, j['formula']), maxReps: toInt(j['maxReps']));

  Json toJson() => {'formula': formula.name, 'maxReps': maxReps};

  @override
  bool operator ==(Object other) => other is OneRepMaxSettings && other.formula == formula && other.maxReps == maxReps;

  @override
  int get hashCode => Object.hash(formula, maxReps);
}

class OneRepMax {
  static double? raw(double weight, int reps, OneRepMaxFormula formula) {
    if (!(weight.isFinite && weight > 0 && reps >= 1)) return null;
    if (reps == 1) return weight;
    switch (formula) {
      case OneRepMaxFormula.epley:
        return weight * (1 + reps / 30);
      case OneRepMaxFormula.brzycki:
        if (reps >= 37) return null;
        return weight * 36 / (37 - reps);
    }
  }

  static double? estimate(double weight, int reps, [OneRepMaxSettings settings = OneRepMaxSettings.standard]) {
    if (reps > settings.maxReps) return null;
    return raw(weight, reps, settings.formula);
  }

  static double? best(ExercisePerformance performance, [OneRepMaxSettings settings = OneRepMaxSettings.standard]) {
    if (performance.measurement != MeasurementType.weightReps) return null;
    double? result;
    for (final s in performance.effectiveSets) {
      if (s.excludedFromEstimates) continue;
      final w = s.weight, r = s.reps;
      if (w == null || r == null) continue;
      final e = estimate(w, r, settings);
      if (e != null && (result == null || e > result)) result = e;
    }
    return result;
  }
}

// MARK: - Trend

class TrendThresholds {
  final int minSessions;
  final int window;
  final double progressingSlope;
  final double decliningSlope;
  final double plateauMaxRange;

  const TrendThresholds({
    this.minSessions = 3,
    this.window = 6,
    this.progressingSlope = 0.01,
    this.decliningSlope = -0.01,
    this.plateauMaxRange = 0.03,
  });

  static const standard = TrendThresholds();

  factory TrendThresholds.fromJson(Json j) => TrendThresholds(
    minSessions: toInt(j['minSessions']),
    window: toInt(j['window']),
    progressingSlope: toDouble(j['progressingSlope']),
    decliningSlope: toDouble(j['decliningSlope']),
    plateauMaxRange: toDouble(j['plateauMaxRange']),
  );

  Json toJson() => {
    'minSessions': minSessions,
    'window': window,
    'progressingSlope': progressingSlope,
    'decliningSlope': decliningSlope,
    'plateauMaxRange': plateauMaxRange,
  };
}

class TrendAnalyzer {
  /// Classifies a chronological series (oldest first).
  static TrendClassification classify(List<double> values, [TrendThresholds t = TrendThresholds.standard]) {
    final minSessions = math.max(3, t.minSessions);
    if (values.length < minSessions || !values.every((v) => v.isFinite)) return TrendClassification.insufficientData;
    final windowSize = math.max(minSessions, t.window);
    final window = values.length > windowSize ? values.sublist(values.length - windowSize) : List.of(values);
    final n = window.length.toDouble();
    final mean = window.reduce((a, b) => a + b) / n;
    if (!(mean > 0)) return TrendClassification.insufficientData;

    final xMean = (n - 1) / 2;
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < window.length; i++) {
      final dx = i - xMean;
      num += dx * (window[i] - mean);
      den += dx * dx;
    }
    final relativeSlope = den > 0 ? (num / den) / mean : 0.0;
    final relativeRange = (window.reduce(math.max) - window.reduce(math.min)) / mean;

    if (relativeSlope >= t.progressingSlope) return TrendClassification.progressing;
    if (relativeSlope <= t.decliningSlope) {
      final last = window.last;
      final earlier = window.sublist(0, window.length - 1);
      if (earlier.isNotEmpty && last < earlier.reduce(math.min)) return TrendClassification.declining;
    }
    if (relativeRange <= t.plateauMaxRange) return TrendClassification.possiblePlateau;
    return TrendClassification.stable;
  }

  /// Trend of an exercise from its comparable performances (chronological, oldest first).
  static TrendClassification classifyPerformances(
    List<ExercisePerformance> performances, {
    OneRepMaxSettings oneRepMax = OneRepMaxSettings.standard,
    TrendThresholds thresholds = TrendThresholds.standard,
  }) {
    final minSessions = math.max(3, thresholds.minSessions);
    if (performances.length < minSessions) return TrendClassification.insufficientData;

    final summaries = performances.map(HistoryAnalyzer.summary).toList();
    if (summaries.isNotEmpty) {
      final lastLoad = summaries.last.workingLoad;
      final run = <double>[];
      for (final s in summaries.reversed) {
        if (!LoadMath.isEqual(s.workingLoad, lastLoad)) break;
        run.add(s.amounts.fold<int>(0, (a, b) => a + b).toDouble());
      }
      if (run.length >= minSessions) return classify(run.reversed.toList(), thresholds);
    }

    final e1rms = <double>[];
    for (final p in performances) {
      final b = OneRepMax.best(p, oneRepMax);
      if (b != null) e1rms.add(b);
    }
    if (e1rms.length == performances.length) return classify(e1rms, thresholds);
    return TrendClassification.insufficientData;
  }
}

// MARK: - HistoryAnalyzer

/// Everything the engine needs (port of ProgressionInput.swift). Calendar = IANA zone + first weekday.
class ProgressionInput {
  final ComparabilityContext context;
  final MeasurementType measurement;
  final ProgressionConfig config;
  final List<ExercisePerformance> history;
  final List<ComparabilityLink> links;
  final DateTime now;
  final String? excludingSessionId;
  final String timeZone;
  final int firstWeekday;
  final String locale;
  final OneRepMaxSettings oneRepMax;
  final TrendThresholds trendThresholds;

  const ProgressionInput({
    required this.context,
    required this.measurement,
    required this.config,
    required this.history,
    this.links = const [],
    required this.now,
    this.excludingSessionId,
    this.timeZone = 'UTC',
    this.firstWeekday = 2,
    this.locale = 'es_AR',
    this.oneRepMax = OneRepMaxSettings.standard,
    this.trendThresholds = TrendThresholds.standard,
  });

  factory ProgressionInput.fromJson(Json j) => ProgressionInput(
    context: ComparabilityContext.fromJson(asJson(j['context'])),
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    config: ProgressionConfig.fromJson(asJson(j['config'])),
    history: listOf(j['history'], (e) => ExercisePerformance.fromJson(asJson(e))),
    links: listOf(j['links'], (e) => ComparabilityLink.fromJson(asJson(e))),
    now: dateFromJson(j['now']),
    excludingSessionId: optUuid(j['excludingSessionId']),
    timeZone: j['timeZone'] as String,
    firstWeekday: toInt(j['firstWeekday']),
    locale: j['locale'] as String,
    oneRepMax: OneRepMaxSettings.fromJson(asJson(j['oneRepMax'])),
    trendThresholds: TrendThresholds.fromJson(asJson(j['trendThresholds'])),
  );
}

class HistoryAnalyzer {
  /// Comparable performances, newest first (section 8.1).
  static List<ExercisePerformance> comparable(ProgressionInput input) {
    final equivalent = ComparabilityResolver(input.links).equivalenceClass(input.context);
    final inClass = _eligible(input).where((p) => equivalent.contains(p.context.identityKey));
    return stableSorted(
      merged(inClass, bySessionOnly: true).where((p) => p.progressionSets.isNotEmpty),
      byPredicate(newestFirst),
    );
  }

  /// Most recent eligible performance of the same exercise in a non-equivalent context.
  static ExercisePerformance? nonEquivalentReference(ProgressionInput input) {
    final equivalent = ComparabilityResolver(input.links).equivalenceClass(input.context);
    final others = _eligible(input).where(
      (p) =>
          p.context.exerciseId.toUpperCase() == input.context.exerciseId.toUpperCase() &&
          !equivalent.contains(p.context.identityKey),
    );
    final sorted = stableSorted(
      merged(others, bySessionOnly: false).where((p) => p.progressionSets.isNotEmpty),
      byPredicate(newestFirst),
    );
    return sorted.isEmpty ? null : sorted.first;
  }

  static Iterable<ExercisePerformance> _eligible(ProgressionInput input) => input.history.where(
    (p) =>
        p.sessionStatus == SessionStatus.completed &&
        !p.isAtypical &&
        p.sessionId.toUpperCase() != input.excludingSessionId?.toUpperCase() &&
        !p.sessionStart.isAfter(input.now) &&
        p.measurement == input.measurement,
  );

  /// Merges logs of the same session (and same normalized context unless `bySessionOnly`).
  static List<ExercisePerformance> merged(Iterable<ExercisePerformance> performances, {required bool bySessionOnly}) {
    final groups = <String, List<ExercisePerformance>>{};
    for (final p in performances) {
      final sessionKey = p.sessionId.toUpperCase();
      final key = bySessionOnly ? sessionKey : '$sessionKey#${p.context.identityKey}';
      groups.putIfAbsent(key, () => []).add(p);
    }
    return groups.values.map((group) {
      final ordered = stableSorted(
        group,
        byPredicate<ExercisePerformance>((a, b) {
          final fa = _firstCompletion(a), fb = _firstCompletion(b);
          if (fa.compareTo(fb) != 0) return fa.isBefore(fb);
          if (a.context.sortKey != b.context.sortKey) return a.context.sortKey.compareTo(b.context.sortKey) < 0;
          return a.exerciseLogId.toUpperCase().compareTo(b.exerciseLogId.toUpperCase()) < 0;
        }),
      );
      final base = ordered.first;
      final sets = ordered.expand((p) => stableSorted(p.sets, byPredicate(setOrder))).toList();
      return base.copyWith(sets: [for (var i = 0; i < sets.length; i++) sets[i].copyWithIndex(i)]);
    }).toList();
  }

  static DateTime _firstCompletion(ExercisePerformance p) {
    DateTime? m;
    for (final s in p.sets) {
      final c = s.completedAt;
      if (c != null && (m == null || c.isBefore(m))) m = c;
    }
    return m ?? distantFuture;
  }

  static bool newestFirst(ExercisePerformance a, ExercisePerformance b) {
    if (a.sessionStart.compareTo(b.sessionStart) != 0) return a.sessionStart.isAfter(b.sessionStart);
    final sa = a.sessionId.toUpperCase(), sb = b.sessionId.toUpperCase();
    if (sa != sb) return sa.compareTo(sb) > 0;
    if (a.context.sortKey != b.context.sortKey) return a.context.sortKey.compareTo(b.context.sortKey) < 0;
    return a.exerciseLogId.toUpperCase().compareTo(b.exerciseLogId.toUpperCase()) < 0;
  }

  /// Total order of sets (same tuple order as Swift).
  static bool setOrder(PerformedSet a, PerformedSet b) {
    if (a.index != b.index) return a.index < b.index;
    final ac = a.completedAt ?? distantFuture;
    final bc = b.completedAt ?? distantFuture;
    if (ac.compareTo(bc) != 0) return ac.isBefore(bc);
    final ka = [a.kind.name, a.status.name, a.weight ?? -1.0, (a.reps ?? -1).toDouble(), (a.seconds ?? -1).toDouble()];
    final kb = [b.kind.name, b.status.name, b.weight ?? -1.0, (b.reps ?? -1).toDouble(), (b.seconds ?? -1).toDouble()];
    final c1 = _compareTuple(ka, kb);
    if (c1 != 0) return c1 < 0;
    final ea = [a.rir ?? -1.0, a.rpe ?? -1.0, a.addedWeight ?? -1.0, a.assistance ?? -1.0];
    final eb = [b.rir ?? -1.0, b.rpe ?? -1.0, b.addedWeight ?? -1.0, b.assistance ?? -1.0];
    final c2 = _compareTuple(ea, eb);
    if (c2 != 0) return c2 < 0;
    return !a.excludedFromEstimates && b.excludedFromEstimates;
  }

  static int _compareTuple(List<Object> a, List<Object> b) {
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      final c = (x is String) ? x.compareTo(y as String) : (x as double).compareTo(y as double);
      if (c != 0) return c;
    }
    return 0;
  }

  /// Most frequent load among progression sets; ties → the heavier load.
  static double? workingLoad(ExercisePerformance performance) {
    final sets = performance.progressionSets;
    if (sets.isEmpty) return null;
    final counts = <int, int>{};
    for (final s in sets) {
      final k = LoadMath.key(s.progressionLoad(performance.measurement));
      counts[k] = (counts[k] ?? 0) + 1;
    }
    MapEntry<int, int>? best;
    for (final e in counts.entries) {
      if (best == null || e.value > best.value || (e.value == best.value && e.key > best.key)) best = e;
    }
    return best!.key * LoadMath.resolution;
  }

  static List<PerformedSet> evaluatedSets(ExercisePerformance performance, int limit) {
    final load = workingLoad(performance);
    if (load == null) return [];
    return performance.progressionSets
        .where((s) => LoadMath.isEqual(s.progressionLoad(performance.measurement), load))
        .take(limit < 0 ? 0 : limit)
        .toList();
  }

  static PerformanceSummary summary(ExercisePerformance performance) {
    final m = performance.measurement;
    return PerformanceSummary(
      sessionId: performance.sessionId,
      exerciseLogId: performance.exerciseLogId,
      date: performance.sessionStart,
      context: performance.context,
      measurement: m,
      workingLoad: workingLoad(performance) ?? 0,
      sets: performance.progressionSets
          .map((s) => SetSummary(LoadMath.normalized(s.progressionLoad(m)), s.amount(m), s.effectiveRIR))
          .toList(),
    );
  }
}
