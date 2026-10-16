import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';

/// Guards the fixture comparison itself: a green fixture run must mean "equal to Swift".
void main() {
  test('jsonDiff detects value, key, length and type differences', () {
    expect(jsonDiff({'a': 1}, {'a': 2}), isNotEmpty);
    expect(jsonDiff({'a': 1, 'b': 'x'}, {'a': 1}), isNotEmpty);
    expect(jsonDiff([1, 2], [1, 2, 3]), isNotEmpty);
    expect(jsonDiff('1', 1), isNotEmpty);
    expect(jsonDiff(62.5, 62.500000001), isNotEmpty);
    expect(jsonDiff({'a': null}, <String, Object?>{}), isNotEmpty);
    expect(jsonDiff(<String, Object?>{}, {'a': null}), isEmpty);
    expect(jsonDiff(1767636000.000002, 1767636000.0), isNotEmpty);
    expect(jsonDiff(0.30000000000000004, 0.3), isEmpty);
  });

  test('a perturbed engine output is rejected', () {
    final c = casesOf(loadFixture('engine_cases.json')).first;
    final out = ProgressionEngine.recommend(ProgressionInput.fromJson((c['input'] as Map).cast())).toJson();
    out['reasonText'] = '${out['reasonText']} ';
    expect(jsonDiff(plain(out), c['output']), isNotEmpty);
  });
}
