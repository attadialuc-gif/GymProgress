import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';

void main() {
  final m = fixtureMap('metrics.json');
  Map<String, Object?> obj(Object? v) => (v as Map).cast<String, Object?>();

  test('1RM estimate', () {
    for (final c in casesOf(m['oneRepMaxEstimate'])) {
      final r = OneRepMax.estimate(
        (c['weight'] as num).toDouble(),
        c['reps'] as int,
        OneRepMaxSettings.fromJson(obj(c['settings'])),
      );
      expect(jsonDiff(r, c['estimate']), isEmpty, reason: '$c → $r');
    }
  });

  test('1RM raw', () {
    for (final c in casesOf(m['oneRepMaxRaw'])) {
      final r = OneRepMax.raw(
        (c['weight'] as num).toDouble(),
        c['reps'] as int,
        enumFromName(OneRepMaxFormula.values, c['formula']),
      );
      expect(jsonDiff(r, c['raw']), isEmpty, reason: '$c → $r');
    }
  });

  test('1RM best', () {
    for (final c in casesOf(m['oneRepMaxBest'])) {
      final r = OneRepMax.best(
        ExercisePerformance.fromJson(obj(c['performance'])),
        OneRepMaxSettings.fromJson(obj(c['settings'])),
      );
      expect(jsonDiff(r, c['best']), isEmpty);
    }
  });

  test('volume', () {
    for (final c in casesOf(m['volume'])) {
      final v = Volume.of(
        ExercisePerformance.fromJson(obj(c['performance'])),
        bodyweight: (c['bodyweight'] as num?)?.toDouble(),
      );
      final diffs = jsonDiff(plain(v.toJson()), c['result']);
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    }
  });

  test('muscle volume', () {
    for (final c in casesOf(m['muscleVolume'])) {
      final work = casesOf(c['work']).map(MuscleWork.fromJson).toList();
      final r = MuscleVolume.compute(
        work,
        TrainingCalendar(timeZone: c['timeZone'] as String),
        indirectFactor: (c['indirectFactor'] as num).toDouble(),
      );
      final diffs = jsonDiff(plain(r.map((e) => e.toJson()).toList()), c['result']);
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    }
  });

  test('personal records', () {
    for (final c in casesOf(m['records'])) {
      final perfs = casesOf(c['performances']).map(ExercisePerformance.fromJson).toList();
      final r = PersonalRecords.compute(perfs, oneRepMax: OneRepMaxSettings.fromJson(obj(c['settings'])));
      final diffs = jsonDiff(plain(r.toJson()), c['result']);
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    }
  });

  test('trend from values', () {
    for (final c in casesOf(m['trendValues'])) {
      final values = (c['values'] as List).map((e) => (e as num).toDouble()).toList();
      expect(TrendAnalyzer.classify(values).name, c['result'], reason: '$values');
    }
  });

  test('trend from performances', () {
    for (final c in casesOf(m['trendPerformances'])) {
      final perfs = casesOf(c['performances']).map(ExercisePerformance.fromJson).toList();
      expect(TrendAnalyzer.classifyPerformances(perfs).name, c['result']);
    }
  });
}
