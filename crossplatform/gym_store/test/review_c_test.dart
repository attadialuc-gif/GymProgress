import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';
import 'package:test/test.dart';

/// Regressions for the independent review of stage C (store): atomic service calls, encode errors
/// as storage errors, case-insensitive ids, es-AR name order, CSV quoting.
class _FailingRepository extends SqliteGymRepository {
  _FailingRepository() : super.open();
  int failSetWritesAfter = -1;
  int _setWrites = 0;

  @override
  void upsertSetLog(SetLog set) {
    if (failSetWritesAfter >= 0 && _setWrites++ >= failSetWritesAfter) {
      throw const GymStoreError(GymStoreErrorKind.storage, 'disk full (simulated)');
    }
    super.upsertSetLog(set);
  }
}

void main() {
  Exercise bench(SqliteGymRepository repo) => ExerciseCatalogService(repo).createCustomExercise(
    name: 'Press de banca',
    measurement: MeasurementType.weightReps,
    equipment: Equipment.barbell,
    loadMode: LoadMode.total,
    primaryMuscles: [MuscleGroup.chest],
  );

  test('a service call that fails half-way leaves nothing behind (startSession)', () {
    final repo = _FailingRepository();
    addTearDown(repo.close);
    final e = bench(repo);
    final routine = RoutineService(repo).createRoutine('Torso', now: DateTime.utc(2026));
    RoutineService(repo).addExercise(routine.id, e.id);
    repo.failSetWritesAfter = 1; // the 2nd set of the session fails
    final workout = WorkoutService(repo, timeZone: 'UTC');
    expect(() => workout.startSession(routine.id, now: DateTime.utc(2026, 1, 2)), throwsA(isA<GymStoreError>()));
    expect(repo.sessions(), isEmpty);
    expect(workout.openSession(), isNull);
    expect(repo.snapshot().exerciseLogs, isEmpty);
    expect(repo.snapshot().setLogs, isEmpty);
  });

  test('a decision whose set prefill fails is not half-saved', () {
    final repo = _FailingRepository();
    addTearDown(repo.close);
    final e = bench(repo);
    final workout = WorkoutService(repo, timeZone: 'UTC');
    final s = workout.startSession(null, now: DateTime.utc(2026, 1, 2));
    final log = workout.addExercise(s.id, e.id, now: DateTime.utc(2026, 1, 2));
    repo.failSetWritesAfter = 0;
    expect(
      () => workout.decide(log.id, const ModifyChoice(weight: 60, reps: [10, 10, 10]), now: DateTime.utc(2026, 1, 2)),
      throwsA(isA<GymStoreError>()),
    );
    expect(repo.decision(log.id), isNull);
    expect(repo.setLogs(log.id).every((x) => x.weight == null && x.targetReps == null), isTrue);
  });

  test('values that cannot be encoded are storage errors and nothing is written', () {
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final goal = Goal(
      exerciseId: newUuid(),
      metric: GoalMetric.weight,
      value: double.infinity,
      createdAt: DateTime.utc(2026),
    );
    expect(
      () => repo.upsertGoal(goal),
      throwsA(isA<GymStoreError>().having((e) => e.kind, 'kind', GymStoreErrorKind.storage)),
    );
    expect(repo.goals(), isEmpty);
  });

  test('initial target with an invalid weight is rejected without changing the config', () {
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final e = bench(repo);
    final workout = WorkoutService(repo, timeZone: 'UTC');
    final s = workout.startSession(null, now: DateTime.utc(2026, 1, 2));
    final log = workout.addExercise(s.id, e.id, now: DateTime.utc(2026, 1, 2));
    expect(
      () => workout.setInitialTarget(log.id, weight: -5, reps: [8], now: DateTime.utc(2026, 1, 2)),
      throwsA(isA<GymStoreError>()),
    );
    expect(repo.exercise(e.id)!.progression.initialWeight, isNull);
  });

  test('id lookups are case-insensitive (Swift UUID equality)', () {
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final e = bench(repo);
    expect(repo.exercise(e.id.toLowerCase())?.id, e.id);
  });

  test('exercise names follow es-AR order (ñ is its own letter after n)', () {
    expect(compareNames('Ñandú', 'Nz'), greaterThan(0));
    expect(compareNames('Ñandú', 'Oa'), lessThan(0));
    expect(compareNames('Muñeca', 'Muz'), lessThan(0));
    expect(compareNames('máquina', 'Maquina'), isNot(0));
    expect(compareNames('Press', 'press'), greaterThan(0));
    expect(compareNames('Mun\u0303eca', 'Muñeca'), 0);
  });

  test('CSV fields with CR, LF or CRLF are always quoted', () {
    expect(ExportService.csvEscape('A\r\nB'), '"A\r\nB"');
    expect(ExportService.csvEscape('A\nB'), '"A\nB"');
    expect(ExportService.csvEscape('a "b", c'), '"a ""b"", c"');
    expect(ExportService.csvText('=SUM(A1)'), "'=SUM(A1)");
    expect(ExportService.csvText('\r\nX'), "'\r\nX");
  });

  test('merge never overwrites a local record whose id differs only in case', () {
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final local = RoutineTemplate(name: 'Local', createdAt: DateTime.utc(2026));
    repo.upsertRoutine(local);
    final incoming = RoutineTemplate(id: local.id.toLowerCase(), name: 'Incoming', createdAt: DateTime.utc(2026));
    repo.merge(GymDatabase(routines: [incoming]), includeSettings: false);
    expect(repo.routines().single.name, 'Local');
  });
}
