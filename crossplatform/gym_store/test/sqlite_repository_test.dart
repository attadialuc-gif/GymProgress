import 'dart:io';

import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// SQLite specifics that the Swift scenarios cannot cover (they run on the JSON store).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gym_sqlite_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path() => '${dir.path}/gym.sqlite';

  test('fresh database is migrated to the current schema version', () {
    final repo = SqliteGymRepository.open(path());
    addTearDown(repo.close);
    expect(repo.schemaVersion, sqliteMigrations.length);
  });

  test('a database from a newer app version is refused (never downgraded)', () {
    SqliteGymRepository.open(path()).close();
    final raw = sqlite3.open(path());
    raw.execute('PRAGMA user_version = ${sqliteMigrations.length + 1}');
    raw.close();
    expect(
      () => SqliteGymRepository.open(path()),
      throwsA(isA<GymStoreError>().having((e) => e.kind, 'kind', GymStoreErrorKind.unsupportedSchemaVersion)),
    );
  });

  test('every completed set is on disk immediately (reopen = process death)', () {
    final repo = SqliteGymRepository.open(path());
    final catalog = ExerciseCatalogService(repo);
    final e = catalog.createCustomExercise(
      name: 'Press de banca',
      measurement: MeasurementType.weightReps,
      equipment: Equipment.barbell,
      loadMode: LoadMode.total,
      primaryMuscles: [MuscleGroup.chest],
    );
    final workout = WorkoutService(repo, timeZone: 'UTC');
    final s = workout.startSession(null, now: DateTime.utc(2026, 1, 5, 18));
    final log = workout.addExercise(s.id, e.id, now: DateTime.utc(2026, 1, 5, 18));
    final set = repo.setLogs(log.id).first
      ..weight = 60
      ..reps = 10;
    workout.updateSet(set);
    workout.completeSet(set.id, now: DateTime.utc(2026, 1, 5, 18, 3));
    // No close(): simulate the process being killed, then reopen the file.
    final reopened = SqliteGymRepository.open(path());
    addTearDown(reopened.close);
    final recovered = WorkoutService(reopened, timeZone: 'UTC').openSession();
    expect(recovered?.id, s.id);
    final sets = reopened.setLogs(log.id);
    expect(sets.first.status, SetStatus.completed);
    expect(sets.first.weight, 60);
    repo.close();
  });

  test('a database with unreadable records is refused (fail closed, like the Swift store)', () {
    final repo = SqliteGymRepository.open(path());
    repo.upsertRoutine(RoutineTemplate(name: 'Torso', createdAt: DateTime.utc(2026)));
    repo.close();
    final raw = sqlite3.open(path());
    raw.execute("INSERT INTO decisions (id, json) VALUES ('X', '{not json')");
    raw.close();
    expect(
      () => SqliteGymRepository.open(path()),
      throwsA(isA<GymStoreError>().having((e) => e.kind, 'kind', GymStoreErrorKind.storage)),
    );
    // Nothing was overwritten: the unreadable row is still there for a rescue.
    final check = sqlite3.open(path());
    addTearDown(check.close);
    expect(check.select("SELECT json FROM decisions WHERE id = 'X'").first['json'], '{not json');
  });

  test('merge is all-or-nothing', () {
    final repo = SqliteGymRepository.open(path());
    addTearDown(repo.close);
    final r1 = RoutineTemplate(name: 'A', createdAt: DateTime.utc(2026));
    // A record that cannot be written (NaN is not JSON) fails half-way through the batch.
    final ok = Goal(exerciseId: newUuid(), metric: GoalMetric.weight, value: 100, createdAt: DateTime.utc(2026));
    final bad = Goal(
      exerciseId: newUuid(),
      metric: GoalMetric.weight,
      value: double.nan,
      createdAt: DateTime.utc(2026),
    );
    final db = GymDatabase(routines: [r1], goals: [ok, bad]);
    expect(() => repo.merge(db, includeSettings: false), throwsA(isA<GymStoreError>()));
    expect(repo.routines(), isEmpty);
    expect(repo.goals(), isEmpty);
    // The database file agrees with memory.
    repo.close();
    final reopened = SqliteGymRepository.open(path());
    addTearDown(reopened.close);
    expect(reopened.routines(), isEmpty);
  });

  test('performance: two years of simulated history (debug data, tests only)', () {
    final repo = SqliteGymRepository.open(path());
    addTearDown(repo.close);
    final catalog = ExerciseCatalogService(repo);
    final exercises = [
      for (final name in ['Press de banca', 'Sentadilla', 'Remo', 'Press militar', 'Peso muerto', 'Dominadas'])
        catalog.createCustomExercise(
          name: name,
          measurement: MeasurementType.weightReps,
          equipment: Equipment.barbell,
          loadMode: LoadMode.total,
          primaryMuscles: [MuscleGroup.chest],
        ),
    ];
    final routine = RoutineService(repo).createRoutine('Full body', now: DateTime.utc(2024, 10, 1));
    for (final e in exercises) {
      RoutineService(repo).addExercise(routine.id, e.id);
    }
    final workout = WorkoutService(repo, timeZone: 'America/Argentina/Buenos_Aires');
    final build = Stopwatch()..start();
    var start = DateTime.utc(2024, 10, 1, 21);
    var sessions = 0;
    repo.batch(() {
      for (var week = 0; week < 104; week++) {
        for (final dayOffset in [0, 2, 4]) {
          final at = start.add(Duration(days: week * 7 + dayOffset));
          final s = workout.startSession(routine.id, now: at);
          for (final log in repo.exerciseLogsOfSession(s.id)) {
            for (final set in repo.setLogs(log.id)) {
              set
                ..weight = 40.0 + (week ~/ 4) * 2.5
                ..reps = 8 + (week % 4)
                ..rir = 2;
              workout.updateSet(set);
              workout.completeSet(set.id, now: at.add(const Duration(minutes: 5)));
            }
          }
          workout.finish(s.id, now: at.add(const Duration(hours: 1)));
          sessions++;
        }
      }
    });
    build.stop();
    expect(sessions, 312);
    expect(repo.snapshot().setLogs.length, 312 * 6 * 3);

    final now = start.add(const Duration(days: 730));
    final t = Stopwatch()..start();
    final s = workout.startSession(routine.id, now: now);
    final logs = repo.exerciseLogsOfSession(s.id);
    for (final log in logs) {
      final state = workout.openExercise(log.id, now: now);
      expect(state.recommendation.evidence, isNotEmpty);
    }
    t.stop();
    final reopen = Stopwatch()..start();
    final again = SqliteGymRepository.open(path());
    reopen.stop();
    again.close();
    final stats = Stopwatch()..start();
    StatsService(
      repo,
      timeZone: 'America/Argentina/Buenos_Aires',
    ).comparison(const StatsPeriod(StatsPeriodKind.last90Days), now: now);
    ConsistencyService(repo, timeZone: 'America/Argentina/Buenos_Aires').streak(now);
    stats.stop();
    // ignore: avoid_print
    print(
      '2 years: build ${build.elapsedMilliseconds} ms, open 6 exercises ${t.elapsedMilliseconds} ms, '
      'reopen ${reopen.elapsedMilliseconds} ms, stats+streak ${stats.elapsedMilliseconds} ms',
    );
    // Opening an exercise during a workout must feel instant.
    expect(t.elapsedMilliseconds / logs.length, lessThan(250));
    expect(reopen.elapsedMilliseconds, lessThan(5000));
  });
}
