import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/routines/routine_exercise_editor.dart';
import 'package:gym_progress/workout/exercise_log_screen.dart';
import 'package:gym_store/gym_store.dart';

import 'helpers.dart';

/// Review of stage D (re-verification): showing kg as rounded lb must never rewrite stored kg.
void main() {
  testWidgets('saving the routine exercise editor in lb without edits keeps the kg values', (tester) async {
    await useTallSurface(tester);
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final model = testModel(repo, TestClock());
    final bench = createBench(model);
    final routine = model.routines.createRoutine('Torso', now: model.now());
    final item = model.routines.addExercise(
      routine.id,
      bench.id,
      override: ProgressionConfig(increment: 2.5, initialWeight: 60, availableWeights: [20, 22.5, 61.5]),
    );
    repo.saveSettings(repo.settings()..weightUnit = WeightUnit.lb);
    final before = repo.routineExercise(item.id)!.progressionOverride!.toJson();

    await tester.pumpWidget(
      host(
        model,
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => RoutineExerciseEditor(itemId: item.id)),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.routineExercise(item.id)!.progressionOverride!.toJson(), before);
  });

  testWidgets('Modificar → Usar in lb without edits keeps the recommended kg exactly', (tester) async {
    await useTallSurface(tester);
    final repo = SqliteGymRepository.open();
    addTearDown(repo.close);
    final clock = TestClock();
    final model = testModel(repo, clock);
    final bench = createBench(model);
    logSession(model, clock, bench.id, 60, [12, 12, 12], rir: 2);
    clock.advance(const Duration(days: 3));
    final s = model.workout.startSession(null, now: model.now());
    final logId = model.workout.addExercise(s.id, bench.id, now: model.now()).id;
    repo.saveSettings(repo.settings()..weightUnit = WeightUnit.lb);

    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    await tester.tap(find.text('Modificar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modifySave')));
    await tester.pumpAndSettle();
    expect(repo.decision(logId)!.finalWeight, 62.5);
    expect(repo.setLogs(logId).every((x) => x.weight == 62.5), isTrue);
  });
}
