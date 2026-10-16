import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/main.dart';
import 'package:gym_progress/workout/exercise_log_screen.dart';
import 'package:gym_store/gym_store.dart';

import 'helpers.dart';

/// Regressions for the independent review of stage D (UI).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('gym_review_d_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A store with history and an open session whose exercise has a modified decision.
  ({AppModel model, String logId}) seeded(String path, TestClock clock) {
    final model = testModel(SqliteGymRepository.open(path), clock);
    final bench = createBench(model);
    logSession(model, clock, bench.id, 60, [12, 12, 12]);
    clock.advance(const Duration(days: 3));
    final s = model.workout.startSession(null, now: model.now());
    final logId = model.workout.addExercise(s.id, bench.id, now: model.now()).id;
    model.workout.openExercise(logId, now: model.now());
    model.workout.decide(logId, const ModifyChoice(weight: 61, reps: [8, 8, 8]), now: model.now());
    return (model: model, logId: logId);
  }

  testWidgets('360 dp and text scale 2.0: the card title stays visible, nothing overflows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clock = TestClock();
    final (:model, :logId) = seeded('${dir.path}/a.sqlite', clock);
    addTearDown(() => (model.repository as SqliteGymRepository).close());
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 2400), textScaler: TextScaler.linear(2.0)),
        child: host(model, ExerciseLogScreen(logId: logId)),
      ),
    );
    await tester.pump();
    final title = tester.getSize(find.text('Podrías subir la carga'));
    expect(title.width, greaterThan(100));
    expect(find.text('Condicionada'), findsOneWidget);
    expect(find.text('Modificada'), findsOneWidget);
  });

  testWidgets('process killed mid-workout: reopening offers to resume and keeps the decision and the card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clock = TestClock();
    final path = '${dir.path}/b.sqlite';
    final first = seeded(path, clock);
    final frozen = first.model.repository.exerciseLog(first.logId)!.frozenRecommendation!.toJson();
    // No orderly shutdown: the process is gone; a new one opens the same file.
    (first.model.repository as SqliteGymRepository).close();
    clock.advance(const Duration(minutes: 30));
    final model = testModel(SqliteGymRepository.open(path), clock);
    addTearDown(() => (model.repository as SqliteGymRepository).close());
    await tester.pumpWidget(GymProgressApp(model: model));
    await tester.pumpAndSettle();
    expect(find.text('Tenés un entrenamiento en curso'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Retomar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de banca'));
    await tester.pumpAndSettle();
    expect(find.text('Modificada'), findsOneWidget);
    expect(model.repository.decision(first.logId)!.finalWeight, 61);
    expect(model.repository.exerciseLog(first.logId)!.frozenRecommendation!.toJson(), frozen);
    expect(model.repository.setLogs(first.logId).every((s) => s.weight == 61), isTrue);
  });

  testWidgets('Android back pops inside the tab, and exits the app only from the tab root', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final clock = TestClock();
    final (:model, :logId) = seeded('${dir.path}/c.sqlite', clock);
    addTearDown(() => (model.repository as SqliteGymRepository).close());
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    model.selectTab(AppTab.workout);
    await tester.pumpWidget(GymProgressApp(model: model));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de banca'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseLogScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseLogScreen), findsNothing);
    expect(find.text('En curso'), findsOneWidget);
    expect(exits, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('a value typed in a row that is torn down is saved', (tester) async {
    await useTallSurface(tester);
    final clock = TestClock();
    final (:model, :logId) = seeded('${dir.path}/d.sqlite', clock);
    addTearDown(() => (model.repository as SqliteGymRepository).close());
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    final set = model.repository.setLogs(logId).first;
    await tester.enterText(find.byKey(Key('amount-${set.id}')), '7');
    await tester.pumpWidget(const SizedBox());
    expect(model.repository.setLog(set.id)!.reps, 7);
  });

  testWidgets('pounds: loads are shown and typed in lb, stored in kg', (tester) async {
    await useTallSurface(tester);
    final clock = TestClock();
    final (:model, :logId) = seeded('${dir.path}/e.sqlite', clock);
    addTearDown(() => (model.repository as SqliteGymRepository).close());
    model.repository.saveSettings(model.settings..weightUnit = WeightUnit.lb);
    await tester.pumpWidget(host(model, ExerciseLogScreen(logId: logId)));
    await tester.pump();
    expect(find.text('132,28 lb × 12, 12, 12'), findsOneWidget); // 60 kg
    final set = model.repository.setLogs(logId)[1];
    await tester.enterText(find.byKey(Key('load-${set.id}')), '135');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(model.repository.setLog(set.id)!.weight, LoadMath.normalized(135 * 0.45359237));
  });
}
