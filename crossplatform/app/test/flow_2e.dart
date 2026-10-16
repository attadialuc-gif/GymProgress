import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/main.dart';
import 'package:gym_store/gym_store.dart';

const _zone = 'America/Argentina/Buenos_Aires';

/// Section 2.E end to end, through the real UI and a real SQLite file:
/// create routine → pick exercise → set target → log sets → save session → reopen the app
/// (new process: the database is closed and reopened) → see history → get the next
/// recommendation computed from what was actually done (2.D-8).
/// Shared by the widget test (Linux CI) and the integration test (Windows/Android device).
Future<void> run2EFlow(WidgetTester tester, String dbPath) async {
  var clock = DateTime.utc(2026, 3, 2, 21); // Monday 18:00 Buenos Aires
  DateTime now() => clock;

  Future<AppModel> launch() async {
    final model = AppModel(SqliteGymRepository.open(dbPath), timeZone: _zone, clock: now)..seedCatalog();
    await tester.pumpWidget(GymProgressApp(model: model));
    await tester.pumpAndSettle();
    return model;
  }

  // Spanish UI: the back button's tooltip is "Atrás", so tap the widget itself.
  Future<void> back() async {
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
  }

  // On a real device the on-screen keyboard can stay open and cover buttons: close it and let
  // the layout settle before locating the next target.
  Future<void> hideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  }

  // Lists build lazily on a phone screen: scroll until the target exists, then make it visible.
  Future<void> reveal(Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 150, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(String text) async {
    await hideKeyboard();
    await reveal(find.text(text));
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  final benchName = ExerciseCatalog.bundled().exercises.firstWhere((e) => e.catalogId == 'barbell-bench-press').name;

  // 1. Create a routine.
  var model = await launch();
  await tapText('Rutinas');
  await tester.tap(find.byKey(const Key('newRoutineMenu')));
  await tester.pumpAndSettle();
  await tapText('Rutina vacía');
  await tester.enterText(find.byType(TextField).last, 'Torso A');
  await tapText('Crear');
  expect(find.text('Torso A'), findsOneWidget);

  // 2. Pick an exercise from the library.
  await tapText('Torso A');
  await reveal(find.byKey(const Key('addRoutineExercise')));
  await tester.tap(find.byKey(const Key('addRoutineExercise')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('exerciseSearch')), 'banca');
  await tester.pumpAndSettle();
  await tapText(benchName);
  expect(find.text(benchName), findsOneWidget);
  expect(find.textContaining('Sin datos: configurá un objetivo inicial'), findsOneWidget);

  // 3. Start the workout and open the exercise: no history → initial target.
  await reveal(find.byKey(const Key('startRoutine')));
  await tester.tap(find.byKey(const Key('startRoutine')));
  await tester.pumpAndSettle();
  expect(find.text('En curso'), findsOneWidget);
  await tapText(benchName);
  expect(find.text('Datos insuficientes'), findsOneWidget);
  await tapText('Definir objetivo inicial');
  await tester.enterText(find.byKey(const Key('modifyWeight')), '60');
  await tester.pump();
  await tester.tap(find.byKey(const Key('modifySave')));
  await tester.pumpAndSettle();

  // 4. Log the sets (weight pre-filled by the target; reps typed).
  final log = model.repository.exerciseLogsOfSession(model.workout.openSession()!.id).single;
  final reps = [10, 10, 9];
  final sets = model.repository.setLogs(log.id);
  expect(sets.length, 3);
  for (var i = 0; i < 3; i++) {
    clock = clock.add(const Duration(minutes: 3));
    await reveal(find.byKey(Key('amount-${sets[i].id}')));
    await tester.enterText(find.byKey(Key('amount-${sets[i].id}')), '${reps[i]}');
    // On a device the on-screen keyboard opens and the layout moves: settle, then locate ✓ again.
    await tester.pumpAndSettle();
    await reveal(find.byKey(Key('complete-${sets[i].id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('complete-${sets[i].id}')));
    await tester.pumpAndSettle();
  }
  final logged = model.repository.setLogs(log.id);
  expect(logged.map((s) => (s.status, s.weight, s.reps)).toList(), [
    (SetStatus.completed, 60.0, 10),
    (SetStatus.completed, 60.0, 10),
    (SetStatus.completed, 60.0, 9),
  ]);

  // 5. Save (finish) the session.
  await back();
  clock = clock.add(const Duration(minutes: 5));
  await hideKeyboard();
  await reveal(find.byKey(const Key('finishWorkout')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('finishWorkout')));
  await tester.pumpAndSettle();
  await tapText('Finalizar');
  expect(model.workout.openSession(), isNull);
  final decisionBefore = model.repository.decision(log.id)!;
  expect(decisionBefore.kind, DecisionKind.modified);
  expect(decisionBefore.finalWeight, 60);

  // 6. "Close the app": tear down the UI, close the database, reopen it in a new model.
  await tester.pumpWidget(const SizedBox());
  (model.repository as SqliteGymRepository).close();
  clock = clock.add(const Duration(days: 2));
  model = await launch();

  // 7. History survives the reload, with the decision.
  await tapText('Progreso');
  await tapText('Historial de entrenamientos');
  expect(find.text('Torso A'), findsWidgets);
  final decisionAfter = model.repository.decision(log.id)!;
  expect(decisionAfter.kind, DecisionKind.modified);
  expect(decisionAfter.finalWeight, 60);
  expect(decisionAfter.decidedAt, decisionBefore.decidedAt);
  await back();

  // 8. Next recommendation, from what was really done (60 × 10, 10, 9), not from the target.
  //    The catalog bench press range is 6–10: +1 rep on the set below the top → 10, 10, 10.
  await tapText(benchName); // exercise progress (charts per context)
  await tapText('Historial completo y recomendación');
  expect(find.textContaining('Próxima sesión: Sumá repeticiones'), findsOneWidget);
  expect(find.text('60 kg × 10, 10, 10'), findsOneWidget);
  final next = model.workout.previewRecommendation(log.exerciseId, now: model.now())!;
  expect(next.action, RecommendationAction.increaseReps);
  expect(next.targetWeight, 60);
  expect(next.targetReps, [10, 10, 10]);
  expect(next.confidence, RecommendationConfidence.conditional); // no RIR recorded
  expect(next.lastPerformance!.amounts, [10, 10, 9]);

  // 9. And it is what the next workout shows on its card.
  await tapText('Rutinas');
  await tapText('Torso A');
  await reveal(find.byKey(const Key('startRoutine')));
  await tester.tap(find.byKey(const Key('startRoutine')));
  await tester.pumpAndSettle();
  await tapText(benchName);
  expect(find.text('Sumá repeticiones'), findsOneWidget);
  expect(find.text('60 kg × 10, 10, 9'), findsOneWidget);

  await tester.pumpWidget(const SizedBox());
  (model.repository as SqliteGymRepository).close();
}
