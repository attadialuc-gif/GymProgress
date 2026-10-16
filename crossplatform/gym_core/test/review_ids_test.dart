import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

/// Review of stage B, finding 1: ids built with constructors (not JSON) may be lowercase. Swift
/// compares UUIDs as values, so the engine must treat them case-insensitively.
void main() {
  const upper = '00000000-0000-0000-0000-0000000000B1';
  final lower = upper.toLowerCase();
  final config = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5);

  ExercisePerformance perf(String exerciseId, String session, String log, DateTime start, List<int> reps) =>
      ExercisePerformance(
        sessionId: session,
        exerciseLogId: log,
        sessionStart: start,
        context: ComparabilityContext(exerciseId: exerciseId, loadMode: LoadMode.total),
        sets: [for (var i = 0; i < reps.length; i++) PerformedSet(index: i, weight: 60, reps: reps[i], rir: 2)],
      );

  test('lowercase exercise id in history is comparable with the uppercase context', () {
    final history = [
      perf(
        lower,
        '00000000-0000-0000-0000-00000000100a',
        '00000000-0000-0000-0000-00000000200a',
        DateTime.utc(2026, 1, 15),
        [10, 9, 9],
      ),
    ];
    final rec = ProgressionEngine.recommend(
      ProgressionInput(
        context: const ComparabilityContext(exerciseId: upper, loadMode: LoadMode.total),
        measurement: MeasurementType.weightReps,
        config: config,
        history: history,
        now: DateTime.utc(2026, 1, 20),
      ),
    );
    expect(rec.action, RecommendationAction.increaseReps);
    expect(
      const ComparabilityResolver([]).areComparable(
        ComparabilityContext(exerciseId: lower, loadMode: LoadMode.total),
        const ComparabilityContext(exerciseId: upper, loadMode: LoadMode.total),
      ),
      isTrue,
    );
  });

  test('the current session is excluded whatever the case of its id', () {
    final history = [
      perf(
        upper,
        '00000000-0000-0000-0000-00000000100A',
        '00000000-0000-0000-0000-00000000200A',
        DateTime.utc(2026, 1, 15),
        [10, 9, 9],
      ),
    ];
    final rec = ProgressionEngine.recommend(
      ProgressionInput(
        context: const ComparabilityContext(exerciseId: upper, loadMode: LoadMode.total),
        measurement: MeasurementType.weightReps,
        config: config,
        history: history,
        now: DateTime.utc(2026, 1, 20),
        excludingSessionId: '00000000-0000-0000-0000-00000000100a',
      ),
    );
    expect(rec.action, RecommendationAction.needsInitialTarget);
  });
}
