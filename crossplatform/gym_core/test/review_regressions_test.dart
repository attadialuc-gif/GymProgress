import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

/// Regressions for the independent review of stage B (inputs the Swift fixtures cannot express).
void main() {
  const bench = '00000000-0000-0000-0000-0000000000B1';
  final now = DateTime.utc(2026, 1, 20, 18);
  final config = ProgressionConfig(targetSets: 3, repMin: 8, repMax: 12, targetRIR: 2, increment: 2.5);

  ExercisePerformance perf(int n, DateTime start, ComparabilityContext context, List<int> reps) => ExercisePerformance(
    sessionId: '00000000-0000-0000-0000-00000000100$n',
    exerciseLogId: '00000000-0000-0000-0000-00000000200$n',
    sessionStart: start,
    context: context,
    sets: [for (var i = 0; i < reps.length; i++) PerformedSet(index: i, weight: 60, reps: reps[i], rir: 2)],
  );

  test('contexts whose sort keys collide are still different contexts (no link → not comparable)', () {
    const a = ComparabilityContext(exerciseId: bench, variantLabel: 'a|b', loadMode: LoadMode.total);
    const b = ComparabilityContext(
      exerciseId: bench,
      variantLabel: 'a',
      equipmentLabel: 'b|',
      loadMode: LoadMode.total,
    );
    expect(a.sortKey, b.sortKey);
    expect(const ComparabilityResolver([]).areComparable(a, b), isFalse);
    final rec = ProgressionEngine.recommend(
      ProgressionInput(
        context: a,
        measurement: MeasurementType.weightReps,
        config: config,
        history: [
          perf(1, DateTime.utc(2026, 1, 15), b, [10, 10, 10]),
        ],
        now: now,
      ),
    );
    expect(rec.action, RecommendationAction.needsInitialTarget);
    expect(rec.reason, RecommendationReason.noComparableHistoryInContext);
  });

  test('UUIDs from JSON are validated and uppercased (lowercase ids from other tools stay comparable)', () {
    expect(uuidFromJson('00000000-0000-0000-0000-0000000000b1'), bench);
    expect(() => uuidFromJson('not-a-uuid'), throwsFormatException);
    final ctx = ComparabilityContext.fromJson({'exerciseId': bench.toLowerCase(), 'loadMode': 'total'});
    expect(ctx.exerciseId, bench);
  });

  test('UTC and local DateTimes of the same instant order identically (determinism)', () {
    const ctx = ComparabilityContext(exerciseId: bench, loadMode: LoadMode.total);
    final start = DateTime.utc(2026, 1, 15, 18);
    final p1 = perf(1, start, ctx, [10, 9, 9]);
    final p2 = perf(2, start.toLocal(), ctx, [11, 10, 10]);
    final forward = ProgressionEngine.recommend(
      ProgressionInput(
        context: ctx,
        measurement: MeasurementType.weightReps,
        config: config,
        history: [p1, p2],
        now: now,
      ),
    );
    final backward = ProgressionEngine.recommend(
      ProgressionInput(
        context: ctx,
        measurement: MeasurementType.weightReps,
        config: config,
        history: [p2, p1],
        now: now,
      ),
    );
    expect(forward.lastPerformance!.sessionId, backward.lastPerformance!.sessionId);
    expect(forward.targetReps, backward.targetReps);
  });

  test('integers are decoded strictly, like Swift JSONDecoder', () {
    expect(toInt(10.0), 10);
    expect(() => toInt(10.5), throwsFormatException);
  });
}
