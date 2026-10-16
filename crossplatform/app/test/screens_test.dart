import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/calendar/calendar_screen.dart';
import 'package:gym_progress/home/home_screen.dart';
import 'package:gym_progress/library/library_screen.dart';
import 'package:gym_progress/profile/profile_screen.dart';
import 'package:gym_progress/progress/exercise_progress_screen.dart';
import 'package:gym_progress/progress/muscle_screens.dart';
import 'package:gym_progress/progress/progress_screen.dart';
import 'package:gym_progress/progress/records_goals_screen.dart';
import 'package:gym_store/gym_store.dart';

import 'helpers.dart';

/// Stage E screens on a phone-sized surface (360 dp): they render real data without overflow and
/// their actions go through the services.
void main() {
  late SqliteGymRepository repo;
  late TestClock clock;
  late AppModel model;
  late Exercise bench;
  late RoutineTemplate routine;

  setUp(() {
    repo = SqliteGymRepository.open();
    clock = TestClock();
    model = testModel(repo, clock);
    model.seedCatalog();
    bench = createBench(model);
    routine = model.routines.createRoutine('Torso A', now: model.now());
    model.routines.addExercise(routine.id, bench.id);
    model.consistency.setWeeklyPlan({2: routine.id, 4: routine.id, 6: routine.id}, from: model.now(), now: model.now());
    // Two years of sessions (3 per week), progressive loads, RIR recorded.
    for (var week = 0; week < 104; week++) {
      for (final day in [0, 2, 4]) {
        final s = model.workout.startSession(routine.id, now: model.now().add(Duration(days: day)));
        for (final log in repo.exerciseLogsOfSession(s.id)) {
          for (final set in repo.setLogs(log.id)) {
            model.workout.updateSet(
              set
                ..weight = 50.0 + (week ~/ 6) * 2.5
                ..reps = 8 + week % 5
                ..rir = 2,
            );
            model.workout.completeSet(set.id, now: model.now().add(Duration(days: day, minutes: 5)));
          }
        }
        model.workout.finish(s.id, now: model.now().add(Duration(days: day, hours: 1)));
      }
      clock.advance(const Duration(days: 7));
    }
    model.repository.upsertGoal(
      Goal(exerciseId: bench.id, metric: GoalMetric.weight, value: 100, createdAt: model.now()),
    );
  });
  tearDown(() => repo.close());

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(model, screen));
    await tester.pumpAndSettle();
  }

  testWidgets('Home: next workout with recommendations, week, streak, volume, records', (tester) async {
    await show(tester, const HomeScreen());
    expect(find.text('Torso A'), findsWidgets);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Racha'), findsOneWidget);
    expect(find.text('Volumen de la semana'), findsOneWidget);
    expect(find.text('Press de banca'), findsWidgets);
  });

  testWidgets('Calendar: month grid, plan and the weekly plan editor (validFrom)', (tester) async {
    await show(tester, const CalendarScreen());
    expect(find.text('Plan semanal vigente'), findsOneWidget);
    expect(find.text('Lunes'), findsOneWidget);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar plan'));
    await tester.pumpAndSettle();
    expect(find.text('Vigente desde'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.scheduleEntries().length, 14); // a new full week appended, the old one kept
  });

  testWidgets('Progress: filters, comparison and exercise chart per context', (tester) async {
    await show(tester, const ProgressScreen());
    expect(find.text('Series efectivas'), findsOneWidget);
    expect(find.text('Volumen externo'), findsOneWidget);
    final interval = const StatsPeriod(StatsPeriodKind.last90Days).interval(model.now(), model.stats.calendar);
    await show(tester, ExerciseProgressScreen(exerciseId: bench.id, interval: interval));
    expect(find.text('Peso'), findsWidgets);
    expect(find.text('Sesiones'), findsOneWidget);
    await tester.tap(find.text('1RM estimado'));
    await tester.pumpAndSettle();
    expect(find.textContaining('estimación, no una medición'), findsOneWidget);
  });

  testWidgets('Muscles: direct and indirect sets, weekly chart', (tester) async {
    final interval = const StatsPeriod(StatsPeriodKind.last30Days).interval(model.now(), model.stats.calendar);
    await show(tester, MuscleVolumeScreen(interval: interval, title: 'Últimos 30 días'));
    expect(find.text('Pecho'), findsOneWidget);
    await show(tester, const MuscleWeeklyScreen(muscle: MuscleGroup.chest));
    expect(find.textContaining('directas'), findsWidgets);
  });

  testWidgets('Records and goals: real vs estimated, goal progress', (tester) async {
    await show(tester, const RecordsGoalsScreen());
    expect(find.text('Peso máximo'), findsOneWidget);
    expect(find.text('Estimación'), findsOneWidget);
    expect(find.text('Levantar 100 kg'), findsOneWidget);
  });

  testWidgets('Library: catalog of 98 + custom, search, criteria editor', (tester) async {
    await show(tester, const LibraryScreen());
    expect(find.text('99 ejercicios'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'banca');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de banca'));
    await tester.pumpAndSettle();
    expect(find.text('Criterios de progresión predeterminados'), findsOneWidget);
    expect(
      find.text('Tiene historial: se puede archivar (deja de aparecer en la biblioteca) pero no eliminar.'),
      findsOneWidget,
    );
  });

  testWidgets('Profile: settings are saved through the repository', (tester) async {
    await show(tester, const ProfileScreen());
    await tester.tap(find.text('Domingo'));
    await tester.pumpAndSettle();
    expect(repo.settings().firstWeekday, 1);
    await tester.scrollUntilVisible(
      find.text('Exportar copia completa (JSON)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Exportar copia completa (JSON)'), findsOneWidget);
    expect(find.text('Importar / restaurar copia…'), findsOneWidget);
  });
}
