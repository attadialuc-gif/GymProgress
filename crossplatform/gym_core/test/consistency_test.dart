import 'package:gym_core/gym_core.dart';
import 'package:test/test.dart';

import 'fixture_util.dart';

void main() {
  final c = fixtureMap('consistency.json');
  DateTime d(Object? v) => dateFromJson(v);
  double s(DateTime x) => dateToJson(x);
  TrainingCalendar cal(Map<String, Object?> x) =>
      TrainingCalendar(timeZone: x['timeZone'] as String, firstWeekday: (x['firstWeekday'] as int?) ?? 2);

  test('training calendar (time zones, DST, first weekday)', () {
    final cases = casesOf(c['calendar']);
    expect(cases.length, greaterThanOrEqualTo(176));
    final failures = <String>[];
    for (final k in cases) {
      final calendar = cal(k);
      final date = d(k['date']);
      final tag = '${k['timeZone']} fw${k['firstWeekday']} ${k['date']}';
      final day = calendar.day(date);
      final actual = {
        'day': s(day),
        'weekday': calendar.weekday(date),
        'weekStart': s(calendar.weekStart(date)),
        'addDays': [
          for (final a in casesOf(k['addDays']))
            {'days': a['days'], 'result': s(calendar.addDays(a['days'] as int, day))},
        ],
        'daysBetweenNext': {
          'other': (k['daysBetweenNext'] as Map)['other'],
          'result': calendar.daysBetween(date, d((k['daysBetweenNext'] as Map)['other'])),
        },
        'daysOfWeek': calendar.daysOfWeek(date).map(s).toList(),
        'startOfMonth': s(calendar.startOfMonth(date)),
        'daysInMonthCount': calendar.daysInMonth(date).length,
      };
      final expected = Map<String, Object?>.of(k)
        ..removeWhere((key, _) => ['timeZone', 'firstWeekday', 'date'].contains(key));
      final diffs = jsonDiff(actual, expected);
      if (diffs.isNotEmpty) failures.add('$tag\n  ${diffs.join('\n  ')}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('schedule with validFrom', () {
    for (final k in casesOf(c['schedule'])) {
      final calendar = cal(k);
      final entries = casesOf(k['entries']).map(ScheduleEntry.fromJson).toList();
      final planned = [
        for (final p in casesOf(k['planned']))
          {'day': p['day'], 'routineId': Schedule.plannedRoutine(d(p['day']), entries, calendar)},
      ];
      final perWeek = [
        for (final p in casesOf(k['plannedDaysPerWeek']))
          {'date': p['date'], 'days': Schedule.plannedDays(d(p['date']), entries, calendar).map(s).toList()},
      ];
      final assignments = Schedule.currentAssignments(
        d(casesOf(k['planned'])[21]['day']),
        entries,
        calendar,
      ).map((key, value) => MapEntry('$key', value));
      final diffs = [
        ...jsonDiff(planned, k['planned']),
        ...jsonDiff(perWeek, k['plannedDaysPerWeek']),
        ...jsonDiff(assignments, k['currentAssignments']),
      ];
      expect(diffs, isEmpty, reason: '${k['name']}\n${diffs.join('\n')}');
    }
  });

  test('weekly plan entries', () {
    for (final k in casesOf(c['weeklyPlanEntries'])) {
      var counter = (k['firstId'] as int) - 1;
      String makeId() {
        counter++;
        return '00000000-0000-0000-0000-${counter.toRadixString(16).toUpperCase().padLeft(12, '0')}';
      }

      final assignments = (k['assignments'] as Map).map(
        (key, value) => MapEntry(int.parse(key as String), value as String),
      );
      final entries = Schedule.weeklyPlanEntries(assignments, d(k['validFrom']), d(k['createdAt']), cal(k), makeId);
      final diffs = jsonDiff(plain(entries.map((e) => e.toJson()).toList()), k['entries']);
      expect(diffs, isEmpty, reason: diffs.join('\n'));
    }
  });

  test('valid session', () {
    for (final k in casesOf(c['validSession'])) {
      final digest = SessionDigest(
        id: 'X',
        start: DateTime.utc(2026),
        status: enumFromName(SessionStatus.values, k['status']),
        effectiveSets: k['effectiveSets'] as int,
      );
      expect(digest.isValid(k['minSets'] as int), k['valid'], reason: '$k');
    }
  });

  test('weekly compliance and streak', () {
    for (final k in casesOf(c['compliance'])) {
      final weeks = Streaks.weeklyCompliance(
        sessions: casesOf(k['sessions']).map(SessionDigest.fromJson).toList(),
        schedule: casesOf(k['schedule']).map(ScheduleEntry.fromJson).toList(),
        minSets: k['minSets'] as int,
        now: d(k['now']),
        calendar: cal(k),
      );
      final diffs = [
        ...jsonDiff(plain(weeks.map((w) => w.toJson()).toList()), k['weeks']),
        ...jsonDiff(plain(Streaks.weeklyStreak(weeks).toJson()), k['streak']),
      ];
      expect(diffs, isEmpty, reason: '${k['name']}\n${diffs.join('\n')}');
    }
  });

  test('training days', () {
    for (final k in casesOf(c['trainingDays'])) {
      final days = Streaks.trainingDays(
        casesOf(k['sessions']).map(SessionDigest.fromJson).toList(),
        k['minSets'] as int,
        TrainingCalendar(timeZone: k['timeZone'] as String),
      );
      expect(jsonDiff(days.map(s).toList(), k['days']), isEmpty);
    }
  });

  test('day-gap streak', () {
    for (final k in casesOf(c['dayGap'])) {
      final r = Streaks.dayGapStreak(
        (k['days'] as List).map(d).toList(),
        k['maxGapDays'] as int,
        d(k['now']),
        TrainingCalendar(timeZone: k['timeZone'] as String),
      );
      expect(jsonDiff(plain(r.toJson()), k['result']), isEmpty, reason: '$k');
    }
  });

  test('weekly goal', () {
    for (final k in casesOf(c['weeklyGoal'])) {
      final r = Streaks.weeklyGoalProgress(
        casesOf(k['sessions']).map(SessionDigest.fromJson).toList(),
        k['goal'] as int,
        k['minSets'] as int,
        d(k['now']),
        TrainingCalendar(timeZone: k['timeZone'] as String),
      );
      expect(
        jsonDiff(
          {'done': r.done, 'goalUsed': r.goal, 'fraction': r.fraction},
          {'done': k['done'], 'goalUsed': k['goalUsed'], 'fraction': k['fraction']},
        ),
        isEmpty,
      );
    }
  });
}
