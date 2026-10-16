/// Ports of Volume.swift and PersonalRecords.swift.
library;

import 'dart:math' as math;

import 'analysis.dart';
import 'calendar.dart';
import 'enums.dart';
import 'json_util.dart';
import 'load_math.dart';
import 'models.dart';

enum VolumeBasis { external, bodyweightIncluded, externalOnlyBodyweightUnknown, notApplicable }

class LoadVolume {
  final double total;
  final double? perSide;
  final VolumeBasis basis;
  final int effectiveSets;
  final int reps;
  final int timeUnderLoadSeconds;

  const LoadVolume(this.total, this.perSide, this.basis, this.effectiveSets, this.reps, this.timeUnderLoadSeconds);

  static const zero = LoadVolume(0, null, VolumeBasis.external, 0, 0, 0);

  Json toJson() {
    final j = <String, Object?>{
      'total': total,
      'basis': basis.name,
      'effectiveSets': effectiveSets,
      'reps': reps,
      'timeUnderLoadSeconds': timeUnderLoadSeconds,
    };
    putOpt(j, 'perSide', perSide);
    return j;
  }
}

class Volume {
  /// Volume of the effective sets (warm-ups and pending sets excluded).
  static LoadVolume of(ExercisePerformance performance, {double? bodyweight}) {
    final sets = performance.effectiveSets;
    final reps = sets.fold<int>(0, (a, s) => a + (s.reps ?? 0));
    final seconds = sets.fold<int>(0, (a, s) => a + (s.seconds ?? 0));
    switch (performance.measurement) {
      case MeasurementType.weightReps:
        final raw = sets.fold<double>(0.0, (a, s) => a + (s.weight ?? 0) * (s.reps ?? 0).toDouble());
        final value = LoadMath.normalized(raw);
        if (performance.context.loadMode == LoadMode.perSide) {
          return LoadVolume(LoadMath.normalized(value * 2), value, VolumeBasis.external, sets.length, reps, seconds);
        }
        return LoadVolume(value, null, VolumeBasis.external, sets.length, reps, seconds);
      case MeasurementType.bodyweightReps:
        final bw = bodyweight;
        if (bw != null && bw.isFinite && bw > 0) {
          final raw = sets.fold<double>(
            0.0,
            (a, s) => a + math.max(0.0, bw + s.netAddedLoad) * (s.reps ?? 0).toDouble(),
          );
          return LoadVolume(LoadMath.normalized(raw), null, VolumeBasis.bodyweightIncluded, sets.length, reps, seconds);
        }
        final raw = sets.fold<double>(0.0, (a, s) => a + (s.addedWeight ?? 0) * (s.reps ?? 0).toDouble());
        return LoadVolume(
          LoadMath.normalized(raw),
          null,
          VolumeBasis.externalOnlyBodyweightUnknown,
          sets.length,
          reps,
          seconds,
        );
      case MeasurementType.duration:
        return LoadVolume(0, null, VolumeBasis.notApplicable, sets.length, reps, seconds);
    }
  }
}

class MuscleWork {
  final ExercisePerformance performance;
  final List<MuscleGroup> primary;
  final List<MuscleInvolvement> secondary;
  const MuscleWork(this.performance, this.primary, this.secondary);

  factory MuscleWork.fromJson(Json j) => MuscleWork(
    ExercisePerformance.fromJson(asJson(j['performance'])),
    listOf(j['primary'], (e) => enumFromName(MuscleGroup.values, e)),
    listOf(j['secondary'], (e) => MuscleInvolvement.fromJson(asJson(e))),
  );
}

class MuscleSetVolume {
  final MuscleGroup muscle;
  final int directSets;
  final double indirectSets;
  final int frequencyDays;
  const MuscleSetVolume(this.muscle, this.directSets, this.indirectSets, this.frequencyDays);

  Json toJson() => {
    'muscle': muscle.name,
    'directSets': directSets,
    'indirectSets': indirectSets,
    'frequencyDays': frequencyDays,
  };
}

/// Swift `rounded(toPlaces:)`: (x · 10^p).rounded() / 10^p, ties away from zero.
double roundedToPlaces(double value, int places) {
  final p = math.pow(10.0, places).toDouble();
  return (value * p).roundToDouble() / p;
}

class MuscleVolume {
  static List<MuscleSetVolume> compute(
    List<MuscleWork> work,
    TrainingCalendar calendar, {
    double indirectFactor = 0.5,
  }) {
    final direct = <MuscleGroup, int>{};
    final indirect = <MuscleGroup, double>{};
    final days = <MuscleGroup, Set<int>>{};
    for (final item in work) {
      if (item.performance.sessionStatus != SessionStatus.completed) continue;
      final count = item.performance.effectiveSets.length;
      if (count <= 0) continue;
      final day = calendar.day(item.performance.sessionStart).microsecondsSinceEpoch;
      final primary = item.primary.toSet();
      for (final muscle in primary) {
        direct[muscle] = (direct[muscle] ?? 0) + count;
        days.putIfAbsent(muscle, () => <int>{}).add(day);
      }
      for (final inv in item.secondary) {
        if (primary.contains(inv.muscle)) continue;
        final factor = math.min(math.max(inv.factor ?? indirectFactor, 0.0), 1.0);
        indirect[inv.muscle] = (indirect[inv.muscle] ?? 0) + count.toDouble() * factor;
      }
    }
    final muscles = {...direct.keys, ...indirect.keys}.toList()..sort(MuscleGroup.compareByRawValue);
    return muscles
        .map((m) => MuscleSetVolume(m, direct[m] ?? 0, roundedToPlaces(indirect[m] ?? 0, 3), days[m]?.length ?? 0))
        .toList();
  }
}

enum RecordKind { maxWeight, maxRepsAtWeight, bestEstimatedOneRepMax, maxSessionVolume }

class PersonalRecord {
  final RecordKind kind;
  final double value;
  final double? weight;
  final int? reps;
  final DateTime date;
  final String sessionId;
  final String exerciseLogId;
  final int? setIndex;
  final bool isEstimated;

  const PersonalRecord({
    required this.kind,
    required this.value,
    this.weight,
    this.reps,
    required this.date,
    required this.sessionId,
    required this.exerciseLogId,
    this.setIndex,
    required this.isEstimated,
  });

  factory PersonalRecord.fromJson(Json j) => PersonalRecord(
    kind: enumFromName(RecordKind.values, j['kind']),
    value: toDouble(j['value']),
    weight: optDouble(j['weight']),
    reps: optInt(j['reps']),
    date: dateFromJson(j['date']),
    sessionId: uuidFromJson(j['sessionId']),
    exerciseLogId: uuidFromJson(j['exerciseLogId']),
    setIndex: optInt(j['setIndex']),
    isEstimated: j['isEstimated'] as bool,
  );

  Json toJson() {
    final j = <String, Object?>{
      'kind': kind.name,
      'value': value,
      'date': dateToJson(date),
      'sessionId': sessionId,
      'exerciseLogId': exerciseLogId,
      'isEstimated': isEstimated,
    };
    putOpt(j, 'weight', weight);
    putOpt(j, 'reps', reps);
    putOpt(j, 'setIndex', setIndex);
    return j;
  }
}

class RecordSummary {
  PersonalRecord? maxWeight;
  PersonalRecord? bestEstimatedOneRepMax;
  PersonalRecord? maxSessionVolume;
  List<PersonalRecord> maxRepsAtWeight;
  List<PersonalRecord> history;

  RecordSummary({
    this.maxWeight,
    this.bestEstimatedOneRepMax,
    this.maxSessionVolume,
    List<PersonalRecord>? maxRepsAtWeight,
    List<PersonalRecord>? history,
  }) : maxRepsAtWeight = maxRepsAtWeight ?? [],
       history = history ?? [];

  Json toJson() {
    final j = <String, Object?>{
      'maxRepsAtWeight': maxRepsAtWeight.map((r) => r.toJson()).toList(),
      'history': history.map((r) => r.toJson()).toList(),
    };
    putOpt(j, 'maxWeight', maxWeight?.toJson());
    putOpt(j, 'bestEstimatedOneRepMax', bestEstimatedOneRepMax?.toJson());
    putOpt(j, 'maxSessionVolume', maxSessionVolume?.toJson());
    return j;
  }
}

class PersonalRecords {
  /// Records from completed weight×reps sessions. Atypical sessions still count.
  static RecordSummary compute(
    List<ExercisePerformance> performances, {
    OneRepMaxSettings oneRepMax = OneRepMaxSettings.standard,
    double? bodyweight,
  }) {
    final ordered = stableSorted(
      performances.where(
        (p) => p.sessionStatus == SessionStatus.completed && p.measurement == MeasurementType.weightReps,
      ),
      byPredicate<ExercisePerformance>((a, b) {
        if (a.sessionStart.compareTo(b.sessionStart) != 0) return a.sessionStart.isBefore(b.sessionStart);
        return a.exerciseLogId.toUpperCase().compareTo(b.exerciseLogId.toUpperCase()) < 0;
      }),
    );

    final summary = RecordSummary();
    final repsAtWeight = <int, PersonalRecord>{};

    for (final perf in ordered) {
      for (final set in perf.effectiveSets) {
        final w = set.weight, r = set.reps;
        if (w == null || r == null) continue;
        final weight = LoadMath.normalized(w);

        PersonalRecord rec(RecordKind kind, double value, bool estimated) => PersonalRecord(
          kind: kind,
          value: value,
          weight: weight,
          reps: r,
          date: perf.sessionStart,
          sessionId: perf.sessionId,
          exerciseLogId: perf.exerciseLogId,
          setIndex: set.index,
          isEstimated: estimated,
        );

        final mw = summary.maxWeight;
        if (weight > 0 && (mw == null || LoadMath.key(weight) > LoadMath.key(mw.value))) {
          final record = rec(RecordKind.maxWeight, weight, false);
          summary.maxWeight = record;
          summary.history.add(record);
        }

        final key = LoadMath.key(weight);
        final existing = repsAtWeight[key];
        if (weight > 0 && (existing == null || r > (existing.reps ?? 0))) {
          repsAtWeight[key] = rec(RecordKind.maxRepsAtWeight, r.toDouble(), false);
        }

        if (!set.excludedFromEstimates) {
          final e1rm = OneRepMax.estimate(weight, r, oneRepMax);
          if (e1rm != null) {
            final value = LoadMath.normalized(e1rm);
            final best = summary.bestEstimatedOneRepMax;
            if (best == null || LoadMath.key(value) > LoadMath.key(best.value)) {
              final record = rec(RecordKind.bestEstimatedOneRepMax, value, true);
              summary.bestEstimatedOneRepMax = record;
              summary.history.add(record);
            }
          }
        }
      }

      final volume = Volume.of(perf, bodyweight: bodyweight).total;
      final mv = summary.maxSessionVolume;
      if (volume > 0 && (mv == null || LoadMath.key(volume) > LoadMath.key(mv.value))) {
        final record = PersonalRecord(
          kind: RecordKind.maxSessionVolume,
          value: volume,
          date: perf.sessionStart,
          sessionId: perf.sessionId,
          exerciseLogId: perf.exerciseLogId,
          isEstimated: false,
        );
        summary.maxSessionVolume = record;
        summary.history.add(record);
      }
    }

    summary.maxRepsAtWeight = stableSorted(repsAtWeight.values, (a, b) => (a.weight ?? 0).compareTo(b.weight ?? 0));
    return summary;
  }
}
