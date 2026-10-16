import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/workout/exercise_log_screen.dart';
import 'package:gym_store/gym_store.dart';

import 'helpers.dart';

/// Section 2.A/2.C on the real screen: the card sits above the sets, shows last session, today's
/// target, the recommendation and its reason; Accept / Modify / Ignore are persisted and never
/// overwritten by reopening the exercise.
void main() {
  late SqliteGymRepository repo;
  late TestClock clock;
  late AppModel model;
  late Exercise bench;

  setUp(() {
    repo = SqliteGymRepository.open();
    clock = TestClock();
    model = testModel(repo, clock);
    bench = createBench(model);
  });
  tearDown(() => repo.close());

  String startWithHistory() {
    logSession(model, clock, bench.id, 60, [12, 12, 12], rir: 2);
    clock.advance(const Duration(days: 3));
    final s = model.workout.startSession(null, now: model.now());
    return model.workout.addExercise(s.id, bench.id, now: model.now()).id;
  }

  testWidgets('card shows last session, target, recommendation and reason above the set table', (tester) async {
    await useTallSurface(tester);
    final logId = startWithHistory();
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();

    expect(find.text('Subí la carga'), findsOneWidget);
    expect(find.text('60 kg × 12, 12, 12'), findsOneWidget);
    expect(find.text('Objetivo de hoy: 3 × 8–12 · RIR 2'), findsOneWidget);
    expect(find.text('62,5 kg'), findsOneWidget);
    expect(find.text('8, 8, 8'), findsOneWidget);
    expect(find.textContaining('Subí a 62,5 kg'), findsOneWidget);
    for (final label in ['Aceptar', 'Modificar', 'Ignorar']) {
      expect(
        find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
        findsOneWidget,
      );
    }
    // The card is above the set table.
    expect(tester.getTopLeft(find.text('Aceptar')).dy, lessThan(tester.getTopLeft(find.text('Serie').first).dy));
  });

  testWidgets('Aceptar persists an accepted decision and pre-fills the sets', (tester) async {
    await useTallSurface(tester);
    final logId = startWithHistory();
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    await tester.tap(find.text('Aceptar'));
    await tester.pump();

    final d = repo.decision(logId)!;
    expect(d.kind, DecisionKind.accepted);
    expect(d.finalWeight, 62.5);
    expect(d.finalReps, [8, 8, 8]);
    expect(repo.setLogs(logId).map((s) => (s.weight, s.targetReps)), everyElement((62.5, 8)));
    expect(find.text('Aceptada'), findsOneWidget);
  });

  testWidgets('Modificar persists the user target (2.D-8) and reopening never overwrites it', (tester) async {
    await useTallSurface(tester);
    final logId = startWithHistory();
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    await tester.tap(find.text('Modificar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('modifyWeight')), '61');
    await tester.pump();
    await tester.tap(find.byKey(const Key('modifySave')));
    await tester.pumpAndSettle();

    final d = repo.decision(logId)!;
    expect(d.kind, DecisionKind.modified);
    expect(d.finalWeight, 61);
    expect(d.recommended.targetWeight, 62.5);
    expect(find.text('Modificada'), findsOneWidget);

    // Leave and reopen the exercise later: the decision and the frozen card are unchanged.
    await tester.pumpWidget(const SizedBox());
    clock.advance(const Duration(minutes: 20));
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    final again = repo.decision(logId)!;
    expect(again.kind, DecisionKind.modified);
    expect(again.finalWeight, 61);
    expect(again.decidedAt, d.decidedAt);
    expect(find.text('Modificada'), findsOneWidget);
    expect(repo.setLogs(logId).every((s) => s.weight == 61), isTrue);
  });

  testWidgets('Ignorar persists an ignored decision and pre-fills nothing', (tester) async {
    await useTallSurface(tester);
    final logId = startWithHistory();
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    await tester.tap(find.text('Ignorar'));
    await tester.pump();
    expect(repo.decision(logId)!.kind, DecisionKind.ignored);
    expect(repo.setLogs(logId).every((s) => s.weight == null && s.targetReps == null), isTrue);
    expect(find.text('Copiar cargas anteriores'), findsOneWidget);
  });

  testWidgets('without history: "Datos insuficientes" and an initial target, never an invented weight', (tester) async {
    await useTallSurface(tester);
    final s = model.workout.startSession(null, now: model.now());
    final logId = model.workout.addExercise(s.id, bench.id, now: model.now()).id;
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    expect(find.text('Datos insuficientes'), findsOneWidget);
    expect(find.text('Sin sesión anterior comparable'), findsOneWidget);
    expect(find.text('Aceptar'), findsNothing);
    await tester.tap(find.text('Definir objetivo inicial'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('modifyWeight'))).controller!.text, isEmpty);
    await tester.enterText(find.byKey(const Key('modifyWeight')), '40');
    await tester.tap(find.byKey(const Key('modifySave')));
    await tester.pumpAndSettle();
    expect(repo.decision(logId)!.kind, DecisionKind.modified);
    expect(repo.exercise(bench.id)!.progression.initialWeight, 40);
  });

  testWidgets('without RIR the recommendation is conditional and says why', (tester) async {
    await useTallSurface(tester);
    logSession(model, clock, bench.id, 60, [12, 12, 12]);
    clock.advance(const Duration(days: 3));
    final s = model.workout.startSession(null, now: model.now());
    final logId = model.workout.addExercise(s.id, bench.id, now: model.now()).id;
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    expect(find.text('Condicionada'), findsOneWidget);
    expect(find.text('Podrías subir la carga'), findsOneWidget);
    expect(find.textContaining('No se registró el RIR/RPE'), findsOneWidget);
  });
}
