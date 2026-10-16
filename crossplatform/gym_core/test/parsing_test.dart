import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';

void main() {
  final p = fixtureMap('parsing.json');

  test('WeightParser.parse', () {
    for (final c in casesOf(p['parse'])) {
      final r = WeightParser.parse(c['text'] as String);
      expect(jsonDiff(r, c['result']), isEmpty, reason: '"${c['text']}" → $r');
    }
  });

  test('WeightParser.parseInt', () {
    for (final c in casesOf(p['parseInt'])) {
      expect(WeightParser.parseInt(c['text'] as String), c['result'], reason: '"${c['text']}"');
    }
  });

  test('SetValidator', () {
    for (final c in casesOf(p['validate'])) {
      final w = c['weight'];
      final issues = SetValidator.validate(
        weight: w == 'inf' ? double.infinity : (w as num?)?.toDouble(),
        reps: c['reps'] as int?,
        seconds: c['seconds'] as int?,
        rir: (c['rir'] as num?)?.toDouble(),
        rpe: (c['rpe'] as num?)?.toDouble(),
      );
      final actual = issues.map((i) => {'kind': i.isError ? 'error' : 'warning', 'message': i.message}).toList();
      expect(jsonDiff(actual, c['issues']), isEmpty, reason: '$c → $actual');
    }
  });

  test('number formatting es_AR / en_US', () {
    for (final c in casesOf(p['number'])) {
      var value = (c['value'] as num).toDouble();
      // JSON cannot carry -0.0: the fixture's "-0" for value 0 comes from Swift's -0.0.
      if (value == 0 && (c['text'] as String).startsWith('-')) value = -0.0;
      final text = GymFormat.number(value, locale: GymLocale.of(c['locale'] as String));
      expect(text, c['text'], reason: '$c');
    }
  });

  test('kg', () {
    for (final c in casesOf(p['kg'])) {
      var value = (c['value'] as num).toDouble();
      if (value == 0 && (c['text'] as String).startsWith('-')) value = -0.0;
      expect(GymFormat.kg(value), c['text']);
    }
  });

  test('load', () {
    for (final c in casesOf(p['load'])) {
      final text = GymFormat.load(
        (c['value'] as num).toDouble(),
        enumFromName(MeasurementType.values, c['measurement']),
        enumFromName(LoadMode.values, c['loadMode']),
        locale: GymLocale.of(c['locale'] as String),
      );
      expect(text, c['text'], reason: '$c');
    }
  });

  test('label normalization (comparability contexts)', () {
    for (final c in casesOf(p['labels'])) {
      final text = c['text'] as String;
      expect(
        ComparabilityContext.normalizeLabel(text),
        c['normalized'],
        reason: '${text.runes.map((r) => r.toRadixString(16)).toList()}',
      );
    }
  });

  test('character folding matches Swift for every tabulated scalar', () {
    for (final c in casesOf(p['fold'])) {
      expect(
        foldDiacritics(String.fromCharCode(c['c'] as int)),
        c['folded'],
        reason: 'U+${(c['c'] as int).toRadixString(16)}',
      );
    }
  });

  test('list', () {
    for (final c in casesOf(p['list'])) {
      expect(GymFormat.list((c['values'] as List).cast<int>()), c['text']);
    }
  });
}
