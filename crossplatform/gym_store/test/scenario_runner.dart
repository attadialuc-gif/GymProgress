// Dart twin of GymCore/Sources/FixtureExporter/ScenarioRunner.swift: runs the store scenarios
// (operations as data) against the Dart services and produces observations normalized with the
// same aliases, so they can be compared with the Swift output.
import 'dart:convert';
import 'dart:io';

import 'package:gym_core/gym_core.dart';
import 'package:gym_store/gym_store.dart';

typedef Op = Map<String, Object?>;

/// Swift `return nil` (no "result" key), as opposed to NSNull (explicit null).
const Object noResult = _NoResult();

class _NoResult {
  const _NoResult();
}

class ScenarioError implements Exception {
  final String message;
  ScenarioError(this.message);
  @override
  String toString() => 'ScenarioError($message)';
}

class ScenarioRunner {
  static const tz = 'America/Argentina/Buenos_Aires';

  final Directory dir = Directory.systemTemp.createTempSync('gym_scenario_');
  final Map<String, ({String path, SqliteGymRepository repo})> _stores = {};
  final Map<String, String> aliasOf = {};
  final Map<String, String> idOf = {};
  final Map<String, String> _blobs = {};
  final Map<String, int> _counters = {};

  ScenarioRunner() {
    _openStore('main', fresh: true);
    for (final e in ExerciseCatalog.bundled().exercises) {
      register(e.uuid, 'cat:${e.catalogId}');
    }
  }

  String exportedBlob(String name) => _blobs[name]!;

  void cleanup() {
    for (final s in _stores.values) {
      s.repo.close();
    }
    dir.deleteSync(recursive: true);
  }

  // MARK: Stores

  void _openStore(String name, {required bool fresh}) {
    final path = _stores[name]?.path ?? '${dir.path}/fixture-$name.sqlite';
    _stores[name]?.repo.close();
    if (fresh) {
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$path$suffix');
        if (f.existsSync()) f.deleteSync();
      }
    }
    _stores[name] = (path: path, repo: SqliteGymRepository.open(path));
  }

  SqliteGymRepository repo(Op op) {
    final name = op['store'] as String? ?? 'main';
    if (!_stores.containsKey(name)) _openStore(name, fresh: true);
    return _stores[name]!.repo;
  }

  WorkoutService _workout(Op op) => WorkoutService(repo(op), timeZone: tz);
  RoutineService _routines(Op op) => RoutineService(repo(op));
  ExerciseCatalogService _catalog(Op op) => ExerciseCatalogService(repo(op));
  HistoryService _history(Op op) => HistoryService(repo(op));
  ConsistencyService _consistency(Op op) => ConsistencyService(repo(op), timeZone: tz);
  StatsService _stats(Op op) => StatsService(repo(op), timeZone: tz);
  ExportService _exporter(Op op) => ExportService(repo(op));

  // MARK: Aliases

  void register(String id, String alias) {
    aliasOf.putIfAbsent(id.toUpperCase(), () => alias);
    idOf.putIfAbsent(alias, () => id.toUpperCase());
  }

  String id(Object? alias) {
    final a = alias is String ? idOf[alias] : null;
    if (a == null) throw ScenarioError('unknown alias $alias');
    return a;
  }

  String _alias(String id) => aliasOf[id.toUpperCase()] ?? '?';

  String _next(String prefix) {
    _counters[prefix] = (_counters[prefix] ?? 0) + 1;
    return '$prefix${_counters[prefix]}';
  }

  void _registerSessionLogs(String session, String alias, GymRepository r) {
    final logs = r.exerciseLogsOfSession(session);
    for (var i = 0; i < logs.length; i++) {
      register(logs[i].id, '$alias.$i');
    }
  }

  // MARK: Values

  DateTime _date(Object? v) => dateFromJson(v is num ? v : 0);
  double? _double(Object? v) => v is num ? v.toDouble() : null;
  ProgressionConfig? _config(Object? v) => v == null ? null : ProgressionConfig.fromJson(asJson(v));
  List<int>? _ints(Object? v) => v is List ? v.map((e) => (e as num).toInt()).toList() : null;

  ComparabilityContext _context(Object? v, Op op) {
    if (v is! Map) throw ScenarioError('context');
    final d = v.cast<String, Object?>();
    if (d.containsKey('log')) return repo(op).exerciseLog(id(d['log']))!.context;
    return ComparabilityContext(
      exerciseId: id(d['exercise']),
      variantLabel: d['variant'] as String?,
      equipmentLabel: d['equipment'] as String?,
      loadMode: enumFromName(LoadMode.values, d['loadMode'] ?? 'total'),
    );
  }

  StatsPeriod _period(Object? v) {
    final d = (v as Map).cast<String, Object?>();
    switch (d['kind']) {
      case 'week':
        return const StatsPeriod(StatsPeriodKind.week);
      case 'last30Days':
        return const StatsPeriod(StatsPeriodKind.last30Days);
      case 'calendarMonth':
        return const StatsPeriod(StatsPeriodKind.calendarMonth);
      case 'last90Days':
        return const StatsPeriod(StatsPeriodKind.last90Days);
      case 'calendarYear':
        return const StatsPeriod(StatsPeriodKind.calendarYear);
      case 'last12Months':
        return const StatsPeriod(StatsPeriodKind.last12Months);
      default:
        return StatsPeriod.custom(DateInterval(_date(d['start']), _date(d['end'])));
    }
  }

  SetLog _setAt(Op op) {
    final sets = repo(op).setLogs(id(op['log']));
    final pos = (op['pos'] as int?) ?? 0;
    if (pos >= sets.length) throw ScenarioError('pos $pos');
    return sets[pos];
  }

  // MARK: Run

  List<Map<String, Object?>> run(List<Op> ops) {
    final observations = <Map<String, Object?>>[];
    for (var step = 0; step < ops.length; step++) {
      final op = ops[step];
      final name = op['op'] as String? ?? '?';
      final entry = <String, Object?>{'step': step, 'op': name};
      try {
        final result = _execute(name, op);
        if (!identical(result, noResult)) entry['result'] = result;
      } on GymStoreError catch (e) {
        entry['error'] = e.kind.name;
      } catch (e) {
        entry['error'] = 'unexpected: $e';
      }
      observations.add(entry);
    }
    return observations.map((o) => _normalize(jsonDecode(jsonEncode(o))) as Map<String, Object?>).toList();
  }

  /// Replaces every UUID string by its alias ("?" when unknown).
  Object? _normalize(Object? value) {
    if (value is String) {
      if (isUuid(value)) return _alias(value);
      return _replaceUuids(value);
    }
    if (value is List) return value.map(_normalize).toList();
    if (value is Map) {
      return {
        for (final e in value.entries)
          (isUuid(e.key as String) ? _alias(e.key as String) : e.key as String): _normalize(e.value),
      };
    }
    return value;
  }

  String _replaceUuids(String text) {
    var result = text;
    for (final e in aliasOf.entries) {
      if (result.contains(e.key)) result = result.replaceAll(e.key, e.value);
    }
    return result;
  }

  Map<String, Object?> _setSummary(SetLog s) => {
    'index': s.index,
    'kind': s.kind.name,
    'status': s.status.name,
    'weight': s.weight,
    'reps': s.reps,
    'seconds': s.seconds,
    'addedWeight': s.addedWeight,
    'assistance': s.assistance,
    'rir': s.rir,
    'rpe': s.rpe,
    'targetReps': s.targetReps,
    'targetSeconds': s.targetSeconds,
    'completedAt': s.completedAt == null ? null : dateToJson(s.completedAt!),
  };

  Object? _decisionJson(RecommendationDecision? d, String log) {
    if (d == null) return null;
    register(d.id, 'decision:${_alias(log)}');
    return d.toJson();
  }

  Map<String, Object?> _summary(ImportSummary s) => {
    'inserted': s.inserted,
    'conflicts': s.conflicts,
    'unchanged': s.unchanged,
  };

  Map<String, Object?> _calendarDay(CalendarDay d) => {
    'date': dateToJson(d.date),
    'status': d.status.name,
    'plannedRoutine': d.plannedRoutineId == null ? null : _alias(d.plannedRoutineId!),
    'plannedRoutineName': d.plannedRoutineName,
    'sessions': (d.sessionIds.map(_alias).toList()..sort()),
    'isToday': d.isToday,
  };

  Map<String, Object?> _totals(PeriodTotals t) => {
    'validSessions': t.validSessions,
    'effectiveSets': t.effectiveSets,
    'volume': t.volume,
    'trainingDays': t.trainingDays,
  };

  String? _optRoutine(Op op) => op['routine'] is String ? id(op['routine']) : null;

  Object? _execute(String name, Op op) {
    final at = _date(op['at']);
    switch (name) {
      // MARK: catalog & routines
      case 'createExercise':
        final e = _catalog(op).createCustomExercise(
          name: op['name'] as String,
          measurement: enumFromName(MeasurementType.values, op['measurement'] ?? 'weightReps'),
          equipment: enumFromName(Equipment.values, op['equipment'] ?? 'barbell'),
          loadMode: enumFromName(LoadMode.values, op['loadMode'] ?? 'total'),
          primaryMuscles: ((op['primary'] as List?) ?? const [])
              .map((m) => enumFromName(MuscleGroup.values, m))
              .toList(),
          secondaryMuscles: ((op['secondary'] as List?) ?? const [])
              .map(
                (m) => MuscleInvolvement(enumFromName(MuscleGroup.values, (m as Map)['muscle']), _double(m['factor'])),
              )
              .toList(),
          increment: _double(op['increment']) ?? 2.5,
          availableWeights: (op['availableWeights'] as List?)?.map(_double).whereType<double>().toList(),
          progression: _config(op['progression']),
        );
        register(e.id, op['alias'] as String);
        return e.toJson();
      case 'seedCatalog':
        final r = _catalog(op).seed(ExerciseCatalog.bundled());
        return {'inserted': r.inserted, 'updated': r.updated};
      case 'createRoutine':
        final r = _routines(op).createRoutine(op['name'] as String, now: at);
        register(r.id, op['alias'] as String);
        return r.toJson();
      case 'createRoutineFromPreset':
        final preset = RoutinePreset.all.firstWhere((p) => p.id == op['preset']);
        final r = _routines(op).createFromPreset(preset, now: at);
        register(r.id, op['alias'] as String);
        final items = repo(op).routineExercises(r.id);
        for (var i = 0; i < items.length; i++) {
          register(items[i].id, '${op['alias']}.$i');
        }
        return {'routine': r.toJson(), 'items': items.map((i) => i.toJson()).toList()};
      case 'addRoutineExercise':
        final item = _routines(op).addExercise(
          id(op['routine']),
          id(op['exercise']),
          override: _config(op['override']),
          restSeconds: op['restSeconds'] as int?,
        );
        register(item.id, op['alias'] as String);
        return item.toJson();
      case 'setSuperset':
        _routines(op).setSuperset((op['items'] as List).map(id).toList(), op['group'] as int?);
        return noResult;
      case 'updateRoutineExerciseOverride':
        final item = repo(op).routineExercise(id(op['item']))!..progressionOverride = _config(op['override']);
        _routines(op).updateRoutineExercise(item);
        return repo(op).routineExercise(item.id)!.toJson();
      case 'duplicateRoutine':
        final copy = _routines(op).duplicateRoutine(id(op['routine']), now: at);
        register(copy.id, op['alias'] as String);
        return {'routine': copy.toJson(), 'items': repo(op).routineExercises(copy.id).map((i) => i.toJson()).toList()};
      case 'duplicateRoutineExercise':
        final dup = _routines(op).duplicateRoutineExercise(id(op['item']));
        register(dup.id, op['alias'] as String);
        return repo(op).routineExercises(dup.routineId).map((i) => i.toJson()).toList();
      case 'moveRoutineExercises':
        _routines(op).moveExercises(id(op['routine']), (op['order'] as List).map(id).toList());
        return repo(op).routineExercises(id(op['routine'])).map((i) => i.toJson()).toList();
      case 'updateExerciseProgression':
        _catalog(op).updateProgression(id(op['exercise']), _config(op['config'])!);
        return repo(op).exercise(id(op['exercise']))!.toJson();
      case 'renameExercise':
        _catalog(op).updateExercise(repo(op).exercise(id(op['exercise']))!..name = op['name'] as String);
        return noResult;
      case 'setExerciseArchived':
        _catalog(op).setArchived(id(op['exercise']), op['archived'] as bool);
        return noResult;
      case 'deleteExercise':
        _catalog(op).deleteExercise(id(op['exercise']));
        return noResult;
      case 'renameRoutine':
        _routines(op).updateRoutine(repo(op).routine(id(op['routine']))!..name = op['name'] as String);
        return noResult;
      case 'setRoutineArchived':
        _routines(op).setArchived(id(op['routine']), op['archived'] as bool);
        return noResult;
      case 'deleteRoutine':
        _routines(op).deleteRoutine(id(op['routine']));
        return noResult;
      case 'routineExercises':
        return repo(op).routineExercises(id(op['routine'])).map((i) => i.toJson()).toList();
      case 'exercise':
        return repo(op).exercise(id(op['exercise']))?.toJson();

      // MARK: sessions
      case 'startSession':
        final routine = op['routine'];
        final s = _workout(op).startSession(routine == null ? null : id(routine), now: at);
        final alias = op['alias'] as String;
        register(s.id, alias);
        _registerSessionLogs(s.id, alias, repo(op));
        return s.toJson();
      case 'addExerciseToSession':
        final log = _workout(op).addExercise(id(op['session']), id(op['exercise']), now: at);
        register(log.id, op['alias'] as String);
        return log.toJson();
      case 'removeExercise':
        _workout(op).removeExercise(id(op['log']));
        return noResult;
      case 'moveExercises':
        _workout(op).moveExercises(id(op['session']), (op['order'] as List).map(id).toList());
        return repo(op).exerciseLogsOfSession(id(op['session'])).map((l) => _alias(l.id)).toList();
      case 'pause':
        _workout(op).pause(id(op['session']), now: at);
        return noResult;
      case 'resume':
        _workout(op).resume(id(op['session']), now: at);
        return noResult;
      case 'finish':
        return _workout(op).finish(id(op['session']), now: at).toJson();
      case 'discard':
        _workout(op).discard(id(op['session']), now: at);
        return noResult;
      case 'setSessionAtypical':
        _workout(op).setSessionAtypical(id(op['session']), op['value'] as bool, now: at);
        return noResult;
      case 'setSessionNotes':
        _workout(op).setSessionNotes(id(op['session']), op['notes'] as String, now: at);
        return noResult;
      case 'setExerciseAtypical':
        _workout(op).setExerciseAtypical(id(op['log']), op['value'] as bool);
        return noResult;
      case 'setExerciseNotes':
        _workout(op).setExerciseNotes(id(op['log']), op['notes'] as String);
        return noResult;
      case 'openSession':
        final s = _workout(op).openSession();
        return s == null ? null : _alias(s.id);
      case 'observeSession':
        final s = repo(op).session(id(op['session']))!;
        return {'session': s.toJson(), 'elapsed': s.elapsed(at)};

      // MARK: recommendation & decisions
      case 'openExercise':
        final state = _workout(op).openExercise(id(op['log']), now: at);
        return {
          'recommendation': state.recommendation.toJson(),
          'decision': _decisionJson(state.decision, state.log.id),
          'sets': state.sets.map(_setSummary).toList(),
        };
      case 'decide':
        final c = (op['choice'] as Map).cast<String, Object?>();
        final DecisionChoice choice = switch (c['kind']) {
          'accept' => const AcceptChoice(),
          'ignore' => const IgnoreChoice(),
          _ => ModifyChoice(
            weight: _double(c['weight']),
            reps: _ints(c['reps']) ?? const [],
            seconds: _ints(c['seconds']),
          ),
        };
        final d = _workout(op).decide(id(op['log']), choice, now: at);
        return _decisionJson(d, id(op['log']));
      case 'setInitialTarget':
        final d = _workout(op).setInitialTarget(
          id(op['log']),
          weight: _double(op['weight']),
          reps: _ints(op['reps']) ?? const [],
          seconds: _ints(op['seconds']),
          now: at,
        );
        return _decisionJson(d, id(op['log']));
      case 'observeDecision':
        final logId = id(op['log']);
        return _decisionJson(repo(op).decision(logId), logId);
      case 'setContext':
        return _workout(op)
            .setContext(
              id(op['log']),
              variantLabel: op['variant'] as String?,
              equipmentLabel: op['equipment'] as String?,
              now: at,
            )
            .toJson();
      case 'switchContextEquivalent':
        return _workout(op)
            .switchContextTreatingAsEquivalent(
              id(op['log']),
              variantLabel: op['variant'] as String?,
              equipmentLabel: op['equipment'] as String?,
              now: at,
            )
            .toJson();
      case 'linkContexts':
        final link = _workout(op).linkContexts(_context(op['a'], op), _context(op['b'], op), now: at);
        register(link.id, _next('link:'));
        return link.toJson();
      case 'observeLog':
        return repo(op).exerciseLog(id(op['log']))!.toJson();
      case 'preview':
        return _workout(op).previewRecommendation(id(op['exercise']), config: _config(op['config']), now: at)?.toJson();
      case 'previewRoutine':
        return _workout(op)
            .previewRecommendations(id(op['routine']), now: at)
            .map((t) => {'item': _alias(t.$1.id), 'exercise': _alias(t.$2.id), 'recommendation': t.$3.toJson()})
            .toList();
      case 'copyPreviousLoads':
        _workout(
          op,
        ).copyPreviousLoads(id(op['log']), allowNonEquivalent: op['allowNonEquivalent'] as bool? ?? false, now: at);
        return repo(op).setLogs(id(op['log'])).map(_setSummary).toList();

      // MARK: sets
      case 'updateSet':
        final s = _setAt(op);
        if (op.containsKey('weight')) s.weight = _double(op['weight']);
        if (op.containsKey('addedWeight')) s.addedWeight = _double(op['addedWeight']);
        if (op.containsKey('assistance')) s.assistance = _double(op['assistance']);
        if (op.containsKey('rir')) s.rir = _double(op['rir']);
        if (op.containsKey('rpe')) s.rpe = _double(op['rpe']);
        if (op.containsKey('reps')) s.reps = op['reps'] as int?;
        if (op.containsKey('seconds')) s.seconds = op['seconds'] as int?;
        if (op['kind'] is String) s.kind = enumFromName(SetKind.values, op['kind']);
        if (op.containsKey('weightText')) s.weight = WeightParser.parse(op['weightText'] as String);
        _workout(op).updateSet(s);
        return _setSummary(repo(op).setLog(s.id)!);
      case 'addSet':
        return _setSummary(
          _workout(op).addSet(id(op['log']), kind: enumFromName(SetKind.values, op['kind'] ?? 'working')),
        );
      case 'completeSet':
        return _setSummary(_workout(op).completeSet(_setAt(op).id, now: at));
      case 'reopenSet':
        _workout(op).reopenSet(_setAt(op).id);
        return noResult;
      case 'removeSet':
        _workout(op).removeSet(_setAt(op).id);
        return repo(op).setLogs(id(op['log'])).map(_setSummary).toList();
      case 'observeSets':
        return repo(op).setLogs(id(op['log'])).map(_setSummary).toList();
      case 'restAdvice':
        final advice = _workout(op).restAdvice(_setAt(op).id);
        return {
          'restSeconds': advice.restSeconds,
          'next': advice.nextExerciseLogId == null ? null : _alias(advice.nextExerciseLogId!),
        };

      // MARK: history & persistence
      case 'reload':
        _openStore(op['store'] as String? ?? 'main', fresh: false);
        return noResult;
      case 'exerciseHistory':
        return _history(op)
            .exerciseHistory(id(op['exercise']))
            .map(
              (e) => {
                'session': _alias(e.session.id),
                'log': _alias(e.log.id),
                'sets': e.sets.map(_setSummary).toList(),
                'decision': e.decision?.kind.name,
                'logName': e.log.snapshot.name,
                'routineName': e.session.routineNameSnapshot,
              },
            )
            .toList();
      case 'sessionSummaries':
        return _history(op)
            .completedSessionSummaries(limit: op['limit'] as int?)
            .map(
              (s) => {
                'session': _alias(s.session.id),
                'exerciseNames': s.exerciseNames,
                'effectiveSets': s.effectiveSets,
                'volume': s.volume,
                'duration': s.duration,
              },
            )
            .toList();
      case 'sessionDigests':
        return _history(op).sessionDigests().map((d) => d.toJson()).toList();
      case 'counts':
        final db = repo(op).snapshot();
        return {
          'exercises': db.exercises.length,
          'routines': db.routines.length,
          'routineExercises': db.routineExercises.length,
          'schedule': db.schedule.length,
          'sessions': db.sessions.length,
          'exerciseLogs': db.exerciseLogs.length,
          'setLogs': db.setLogs.length,
          'decisions': db.decisions.length,
          'links': db.comparabilityLinks.length,
          'goals': db.goals.length,
        };
      case 'saveSettings':
        final dict = repo(op).settings().toJson()..addAll((op['patch'] as Map).cast<String, Object?>());
        dict.removeWhere((k, v) => v == null);
        final settings = UserSettings.fromJson(dict);
        repo(op).saveSettings(settings);
        return settings.toJson();
      case 'settings':
        return repo(op).settings().toJson();

      // MARK: export / import
      case 'export':
        _blobs[op['blob'] as String] = _exporter(op).exportJson(now: at);
        return noResult;
      case 'import':
        return _summary(_exporter(op).importJson(_blobs[op['blob'] as String]!));
      case 'importRaw':
        return _summary(_exporter(op).importJson(jsonEncode(op['json'])));
      case 'importText':
        return _summary(_exporter(op).importJson(op['text'] as String));
      case 'snapshotEquals':
        final a = repo({'store': op['a']}).snapshot()..exportedAt = null;
        final b = repo({'store': op['b']}).snapshot()..exportedAt = null;
        return canonicalJson(a.toJson()) == canonicalJson(b.toJson());
      case 'csv':
        return _exporter(op).exportSetsCsv();
      case 'mergeRaw':
        repo(
          op,
        ).merge(GymDatabase.fromJson(asJson(op['json'])), includeSettings: op['includeSettings'] as bool? ?? false);
        return noResult;
      case 'scheduleEntries':
        return repo(op).scheduleEntries().map((e) => e.toJson()).toList();

      // MARK: consistency
      case 'setWeeklyPlan':
        final assignments = <int, String>{};
        ((op['assignments'] as Map?) ?? const {}).forEach((k, v) => assignments[int.parse(k as String)] = id(v));
        final before = repo(op).scheduleEntries().map((e) => e.id).toSet();
        _consistency(op).setWeeklyPlan(assignments, from: _date(op['from']), now: at);
        final added = repo(op).scheduleEntries().where((e) => !before.contains(e.id)).toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
        for (final e in added) {
          register(e.id, _next('plan:'));
        }
        return noResult;
      case 'calendarWeek':
        return _consistency(op).week(_date(op['date']), now: at).map(_calendarDay).toList();
      case 'calendarMonth':
        return _consistency(op).month(_date(op['date']), now: at).map(_calendarDay).toList();
      case 'weekSummary':
        final w = _consistency(op).weekSummary(at);
        return {
          'weekStart': dateToJson(w.weekStart),
          'planned': w.planned,
          'validSessions': w.validSessions,
          'weeklyGoal': w.weeklyGoal,
          'goalFraction': w.goalFraction,
          'goalMet': w.goalMet,
        };
      case 'streak':
        final s = _consistency(op).streak(at);
        return {'result': s.result.toJson(), 'definition': s.definition};
      case 'plan':
        return _consistency(op).plan(_date(op['asOf'])).map((k, v) => MapEntry('$k', _alias(v)));
      case 'plannedRoutine':
        final r = _consistency(op).plannedRoutine(_date(op['date']));
        return r == null ? null : _alias(r);
      case 'nextPlanned':
        final n = _consistency(op).nextPlannedWorkout(at);
        return n == null ? null : {'date': dateToJson(n.date), 'routine': _alias(n.routineId)};

      // MARK: stats
      case 'periodIntervals':
        final p = _period(op['period']);
        final cal = _stats(op).calendar;
        final comparable = p.comparableIntervals(at, cal);
        List<double> iv(DateInterval i) => [dateToJson(i.start), dateToJson(i.end)];
        return {
          'interval': iv(p.interval(at, cal)),
          'previous': iv(p.previousInterval(at, cal)),
          'comparableCurrent': iv(comparable.current),
          'comparablePrevious': iv(comparable.previous),
        };
      case 'comparison':
        final c = _stats(op).comparison(_period(op['period']), now: at, routineId: _optRoutine(op));
        return {'current': _totals(c.current), 'previous': _totals(c.previous), 'isToDate': c.isToDate};
      case 'totals':
        return _totals(
          _stats(op).totals(DateInterval(_date(op['start']), _date(op['end'])), routineId: _optRoutine(op)),
        );
      case 'contextClasses':
        return _stats(op)
            .contextClasses(id(op['exercise']))
            .map(
              (c) => {
                'label': c.label,
                'representative': c.representative.toJson(),
                'contexts': (c.contextSortKeys.toList()..sort()),
                'lastUsed': dateToJson(c.lastUsed),
              },
            )
            .toList();
      case 'exerciseSeries':
        final s = _stats(op);
        final classes = s.contextClasses(id(op['exercise']));
        final cls = op['classIndex'] is int ? classes[op['classIndex'] as int] : null;
        final interval = op.containsKey('start') ? DateInterval(_date(op['start']), _date(op['end'])) : null;
        return s
            .exerciseSeries(id(op['exercise']), interval: interval, contextClass: cls, routineId: _optRoutine(op))
            .map(
              (p) => {
                'log': _alias(p.exerciseLogId),
                'date': dateToJson(p.date),
                'measurement': p.measurement.name,
                'loadMode': p.loadMode.name,
                'workingLoad': p.workingLoad,
                'totalAmount': p.totalAmount,
                'bestSetAmount': p.bestSetAmount,
                'estimatedOneRepMax': p.estimatedOneRepMax,
                'volume': p.volume,
                'effectiveSets': p.effectiveSets,
                'isAtypical': p.isAtypical,
              },
            )
            .toList();
      case 'muscleVolume':
        return _stats(op)
            .muscleVolume(DateInterval(_date(op['start']), _date(op['end'])), routineId: _optRoutine(op))
            .map((m) => m.toJson())
            .toList();
      case 'weeklyDirectSets':
        return _stats(op)
            .weeklyDirectSets(enumFromName(MuscleGroup.values, op['muscle']), weeks: op['weeks'] as int, now: at)
            .map(
              (w) => {'weekStart': dateToJson(w.weekStart), 'directSets': w.directSets, 'indirectSets': w.indirectSets},
            )
            .toList();
      case 'records':
        final s = _stats(op);
        final classes = s.contextClasses(id(op['exercise']));
        final cls = op['classIndex'] is int ? classes[op['classIndex'] as int] : null;
        return s.records(id(op['exercise']), contextClass: cls).toJson();
      case 'recentRecords':
        return _stats(op)
            .recentRecords(days: op['days'] as int, now: at, limit: op['limit'] as int? ?? 5)
            .map(
              (r) => {
                'exercise': _alias(r.exerciseId),
                'exerciseName': r.exerciseName,
                'contextLabel': r.contextLabel,
                'record': r.record.toJson(),
              },
            )
            .toList();
      case 'addGoal':
        final goal = Goal(
          exerciseId: id(op['exercise']),
          metric: enumFromName(GoalMetric.values, op['metric']),
          value: _double(op['value'])!,
          weight: _double(op['weight']),
          createdAt: at,
        );
        repo(op).upsertGoal(goal);
        register(goal.id, op['alias'] as String);
        return noResult;
      case 'goalProgress':
        return _stats(op)
            .goalProgress(now: at)
            .map(
              (g) => {
                'goal': g.goal.toJson(),
                'current': g.current,
                'fraction': g.fraction,
                'achieved': g.achieved,
                'achievedOn': g.achievedOn == null ? null : dateToJson(g.achievedOn!),
              },
            )
            .toList();
      case 'refreshGoals':
        return _stats(op).refreshGoals(now: at).map((g) => g.toJson()).toList();
      default:
        throw ScenarioError('bad op $name');
    }
  }
}
