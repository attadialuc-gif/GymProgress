import 'dart:convert';

import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';

void main() {
  final cases = casesOf(loadFixture('engine_cases.json'));

  group('engine fixtures (Swift DoubleProgressionStrategy)', () {
    test('fixture set is complete', () {
      expect(cases.length, greaterThanOrEqualTo(72));
      for (var i = 1; i <= 8; i++) {
        expect(cases.where((c) => (c['name'] as String).startsWith('2D-$i ')), isNotEmpty, reason: 'case 2.D-$i');
      }
    });

    for (final c in cases) {
      test(c['name'], () {
        final input = ProgressionInput.fromJson((c['input'] as Map).cast<String, Object?>());
        final output = ProgressionEngine.recommend(input).toJson();
        final diffs = jsonDiff(plain(output), c['output']);
        expect(diffs, isEmpty, reason: diffs.join('\n'));
      });
    }
  });

  group('determinism', () {
    test('mixed group: every ordering yields the same recommendation', () {
      final mixed = cases.where((c) => c['group'] == 'mixed').toList();
      expect(mixed.length, greaterThanOrEqualTo(5));
      final outputs = mixed
          .map(
            (c) =>
                jsonEncode(ProgressionEngine.recommend(ProgressionInput.fromJson((c['input'] as Map).cast())).toJson()),
          )
          .toSet();
      expect(outputs.length, 1);
    });

    test('set-order group: same sets in any order yield the same recommendation', () {
      final group = cases.where((c) => c['group'] == 'set-order').toList();
      expect(group.length, 2);
      final outputs = group
          .map(
            (c) =>
                jsonEncode(ProgressionEngine.recommend(ProgressionInput.fromJson((c['input'] as Map).cast())).toJson()),
          )
          .toSet();
      expect(outputs.length, 1);
    });

    test('repeated runs are identical', () {
      for (final c in cases) {
        final input = ProgressionInput.fromJson((c['input'] as Map).cast());
        final a = jsonEncode(ProgressionEngine.recommend(input).toJson());
        final b = jsonEncode(ProgressionEngine.recommend(input).toJson());
        expect(a, b, reason: c['name'] as String);
      }
    });
  });

  group('engine helpers', () {
    final h = fixtureMap('engine_helpers.json');

    test('workingLoad tie → heavier', () {
      for (final c in casesOf(h['workingLoad'])) {
        final p = ExercisePerformance.fromJson((c['performance'] as Map).cast());
        expect(HistoryAnalyzer.workingLoad(p), c['workingLoad']);
      }
    });

    test('sanitize', () {
      for (final c in casesOf(h['sanitize'])) {
        final raw = Map<String, Object?>.of((c['config'] as Map).cast());
        raw.removeWhere((k, v) => v == null);
        final nan = raw['increment'] == 'nan';
        if (nan) raw['increment'] = 0;
        final config = ProgressionConfig.fromJson(raw);
        if (nan) config.increment = double.nan;
        final diffs = jsonDiff(plain(config.sanitized().toJson()), c['sanitized']);
        expect(diffs, isEmpty, reason: diffs.join('\n'));
      }
    });

    test('nextLoad', () {
      for (final c in casesOf(h['nextLoad'])) {
        final weights = (c['availableWeights'] as List?)?.map((e) => (e as num).toDouble()).toList();
        final next = LoadMath.nextLoad((c['current'] as num).toDouble(), (c['increment'] as num).toDouble(), weights);
        expect(jsonDiff(next, c['next']), isEmpty, reason: '$c → $next');
      }
    });

    test('normalize and key', () {
      for (final c in casesOf(h['normalize'])) {
        final v = (c['value'] as num).toDouble();
        expect(jsonDiff(LoadMath.normalized(v), c['normalized']), isEmpty, reason: '$v');
        expect(LoadMath.key(v), c['key']);
      }
    });
  });
}
