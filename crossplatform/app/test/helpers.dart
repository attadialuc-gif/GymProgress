import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_core/gym_core.dart';
import 'package:gym_progress/app_model.dart';
import 'package:gym_progress/ui/theme.dart';
import 'package:gym_store/gym_store.dart';

const testZone = 'America/Argentina/Buenos_Aires';

/// Mutable test clock (the app reads the clock only through AppModel.now()).
class TestClock {
  DateTime now = DateTime.utc(2026, 3, 2, 21); // Monday 18:00 in Buenos Aires
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

AppModel testModel(SqliteGymRepository repo, TestClock clock) => AppModel(repo, timeZone: testZone, clock: clock.call);

/// Hosts one screen with the app theme, Spanish localizations and the model.
Widget host(AppModel model, Widget child) => AppScope(
  model: model,
  child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    locale: const Locale('es', 'AR'),
    supportedLocales: const [Locale('es', 'AR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: child,
  ),
);

Exercise createBench(AppModel model) => model.catalog.createCustomExercise(
  name: 'Press de banca',
  measurement: MeasurementType.weightReps,
  equipment: Equipment.barbell,
  loadMode: LoadMode.total,
  primaryMuscles: [MuscleGroup.chest],
  progression: ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5),
);

/// A finished session through the services: weight × reps per set, optional RIR.
void logSession(AppModel model, TestClock clock, String exerciseId, double weight, List<int> reps, {double? rir}) {
  final w = model.workout;
  final s = w.startSession(null, now: model.now());
  final log = w.addExercise(s.id, exerciseId, now: model.now());
  final sets = model.repository.setLogs(log.id);
  for (var i = 0; i < reps.length; i++) {
    final set = sets[i]
      ..weight = weight
      ..reps = reps[i]
      ..rir = rir;
    w.updateSet(set);
    w.completeSet(set.id, now: model.now());
  }
  w.finish(s.id, now: model.now().add(const Duration(hours: 1)));
}

/// Large surface so whole screens fit (phone-sized logic, no scrolling surprises).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
