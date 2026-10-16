import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/workout/exercise_log_screen.dart';
import 'package:gym_store/gym_store.dart';

import 'helpers.dart';

/// Logging speed and integrity: typed values are saved, comma or dot decimals, one-tap completion
/// with the visible target, and a typo never becomes data.
void main() {
  late SqliteGymRepository repo;
  late TestClock clock;
  late AppModel model;
  late String logId;

  setUp(() {
    repo = SqliteGymRepository.open();
    clock = TestClock();
    model = testModel(repo, clock);
    final bench = createBench(model);
    final s = model.workout.startSession(null, now: model.now());
    logId = model.workout.addExercise(s.id, bench.id, now: model.now()).id;
  });
  tearDown(() => repo.close());

  Future<void> open(WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
  }

  testWidgets('typing weight (comma) and reps, then ✓, saves and completes the set', (tester) async {
    await open(tester);
    final set = repo.setLogs(logId).first;
    await tester.enterText(find.byKey(Key('load-${set.id}')), '62,5');
    await tester.enterText(find.byKey(Key('amount-${set.id}')), '10');
    await tester.tap(find.byKey(Key('complete-${set.id}')));
    await tester.pump();
    final saved = repo.setLog(set.id)!;
    expect(saved.status, SetStatus.completed);
    expect(saved.weight, 62.5);
    expect(saved.reps, 10);
    expect(saved.completedAt, isNotNull);
    expect(model.restTimer.isRunning, isTrue);
  });

  testWidgets('a dot works too, and the value survives leaving the field', (tester) async {
    await open(tester);
    final set = repo.setLogs(logId)[1];
    await tester.enterText(find.byKey(Key('load-${set.id}')), '61.5');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(repo.setLog(set.id)!.weight, 61.5);
    expect(repo.setLog(set.id)!.status, SetStatus.pending);
  });

  testWidgets('one tap uses the visible target reps after Aceptar/Modificar', (tester) async {
    model.workout.decide(logId, const ModifyChoice(weight: 60, reps: [10, 10, 10]), now: model.now());
    await open(tester);
    final set = repo.setLogs(logId).first;
    await tester.tap(find.byKey(Key('complete-${set.id}')));
    await tester.pump();
    final saved = repo.setLog(set.id)!;
    expect(saved.status, SetStatus.completed);
    expect((saved.weight, saved.reps), (60.0, 10));
  });

  testWidgets('an invalid number is reported and never stored', (tester) async {
    await open(tester);
    final set = repo.setLogs(logId).first;
    await tester.enterText(find.byKey(Key('load-${set.id}')), '6,2,5');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(repo.setLog(set.id)!.weight, isNull);
    expect(find.text('Peso inválido: usá coma o punto decimal.'), findsOneWidget);
  });

  testWidgets('completing without values is refused with a Spanish message', (tester) async {
    await open(tester);
    final set = repo.setLogs(logId).first;
    await tester.tap(find.byKey(Key('complete-${set.id}')));
    await tester.pump();
    expect(repo.setLog(set.id)!.status, SetStatus.pending);
    expect(model.errorMessage, 'Completá peso y repeticiones antes de marcar la serie.');
  });

  testWidgets('a completed set can be reopened', (tester) async {
    await open(tester);
    final set = repo.setLogs(logId).first;
    await tester.enterText(find.byKey(Key('load-${set.id}')), '60');
    await tester.enterText(find.byKey(Key('amount-${set.id}')), '8');
    await tester.tap(find.byKey(Key('complete-${set.id}')));
    await tester.pump();
    await tester.tap(find.byKey(Key('complete-${set.id}')));
    await tester.pump();
    expect(repo.setLog(set.id)!.status, SetStatus.pending);
    expect(repo.setLog(set.id)!.reps, 8);
  });
}
