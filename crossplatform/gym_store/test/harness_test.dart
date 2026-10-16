import 'package:test/test.dart';

import 'fixture_util.dart';
import 'scenario_runner.dart';

/// Guards the scenario comparison itself: a green run must mean "same observations as Swift".
void main() {
  final scenarios = casesOf(loadFixture('store_scenarios.json'));

  test('a perturbed observation is detected', () {
    final runner = ScenarioRunner();
    addTearDown(runner.cleanup);
    final scenario = scenarios.first;
    final actual = runner.run(casesOf(scenario['ops']));
    expect(jsonDiff(actual, scenario['observations']), isEmpty);
    final perturbed = [...actual]..[0] = {...actual[0], 'result': 'changed'};
    expect(jsonDiff(perturbed, scenario['observations']), isNotEmpty);
  });

  test('every op runs (no unexpected errors) and the expected errors are the Swift ones', () {
    var expectedErrors = 0, actualErrors = 0;
    for (final scenario in scenarios) {
      final runner = ScenarioRunner();
      final actual = runner.run(casesOf(scenario['ops']));
      runner.cleanup();
      for (final o in actual) {
        final error = o['error'] as String?;
        expect(error?.startsWith('unexpected') ?? false, isFalse, reason: '${scenario['name']}: $o');
        if (error != null) actualErrors++;
      }
      expectedErrors += casesOf(scenario['observations']).where((o) => o['error'] != null).length;
    }
    expect(expectedErrors, 15);
    expect(actualErrors, expectedErrors);
  });

  test('observations are non-trivial (results compared, not just op names)', () {
    var withResult = 0;
    for (final scenario in scenarios) {
      withResult += casesOf(scenario['observations']).where((o) => o.containsKey('result')).length;
    }
    expect(withResult, greaterThan(500));
  });
}
