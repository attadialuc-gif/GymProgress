import 'dart:convert';
import 'dart:io';

import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';
import 'scenario_runner.dart';

/// Store scenarios exported from the Swift GymStore tests (persistence, decisions never
/// overwritten, session recovery, import/export, calendar, stats…), replayed against the Dart
/// services on SQLite. Observations must match Swift exactly (UUIDs replaced by aliases).
void main() {
  final scenarios = casesOf(loadFixture('store_scenarios.json'));

  test('fixture set is complete', () => expect(scenarios.length, greaterThanOrEqualTo(42)));

  for (final scenario in scenarios) {
    test('scenario: ${scenario['name']}', () {
      final runner = ScenarioRunner();
      addTearDown(runner.cleanup);
      final ops = casesOf(scenario['ops']);
      final actual = runner.run(ops);
      final expected = scenario['observations'] as List;
      final diffs = jsonDiff(actual, expected);
      expect(diffs.take(15).toList(), isEmpty, reason: '${diffs.length} differences');
    });
  }

  group('cross-platform exchange (JSON with schemaVersion)', () {
    test('a Swift export imports into the Dart store without loss and re-import inserts nothing', () {
      final text = File(fixturePath('export_from_swift.json')).readAsStringSync();
      final file = GymDatabase.fromJson(asJson(jsonDecode(text)));
      final repo = SqliteGymRepository.open();
      addTearDown(repo.close);
      final service = ExportService(repo);

      final first = service.importJson(text);
      final total =
          file.exercises.length +
          file.routines.length +
          file.routineExercises.length +
          file.schedule.length +
          file.sessions.length +
          file.exerciseLogs.length +
          file.setLogs.length +
          file.decisions.length +
          file.comparabilityLinks.length +
          file.goals.length;
      expect(first.inserted, total);
      expect(first.conflicts, 0);

      final snapshot = repo.snapshot();
      String key(Json j) => canonicalJson(j);
      Set<String> all(GymDatabase db) => {
        ...db.exercises.map((e) => key(e.toJson())),
        ...db.routines.map((e) => key(e.toJson())),
        ...db.routineExercises.map((e) => key(e.toJson())),
        ...db.schedule.map((e) => key(e.toJson())),
        ...db.sessions.map((e) => key(e.toJson())),
        ...db.exerciseLogs.map((e) => key(e.toJson())),
        ...db.setLogs.map((e) => key(e.toJson())),
        ...db.decisions.map((e) => key(e.toJson())),
        ...db.comparabilityLinks.map((e) => key(e.toJson())),
        ...db.goals.map((e) => key(e.toJson())),
      };
      expect(all(snapshot), all(file));
      expect(key(snapshot.settings.toJson()), key(file.settings.toJson()));

      final second = service.importJson(text);
      expect(second.inserted, 0);
      expect(second.conflicts, 0);
      expect(second.unchanged, total);

      // The Dart export is written for the Swift side to verify (see docs/PROGRESS.md, stage C).
      final out = Platform.environment['GYM_DART_EXPORT'];
      final exported = service.exportJson(now: DateTime.utc(2026, 10, 16, 12));
      if (out != null) File(out).writeAsStringSync(exported);
      final reimported = SqliteGymRepository.open();
      addTearDown(reimported.close);
      expect(ExportService(reimported).importJson(exported).inserted, total);
      expect(all(reimported.snapshot()), all(file));
    });
  });
}
