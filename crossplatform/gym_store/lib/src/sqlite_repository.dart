/// SQLite implementation of [GymRepository] (D-102). Records are kept in memory (same indexes and
/// ordering as Swift's `JSONGymRepository`) and written through to SQLite: every mutation is one
/// transaction (WAL, synchronous=FULL), so a completed set survives a crash or process death.
/// Memory changes only after the write succeeds. Like the Swift store, a database with unreadable
/// records is refused (fail closed): nothing is overwritten and nothing is silently exported.
library;

import 'dart:convert';

import 'package:gym_core/gym_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'records.dart';
import 'repository.dart';

class _Op {
  final String sql;
  final List<Object?> params;

  /// Record payload, encoded inside the transaction (an encoding error rolls everything back).
  final Object? json;
  const _Op(this.sql, this.params, [this.json]);
}

/// Versioned schema. Index i upgrades from `user_version` i to i + 1. Never edit a shipped step:
/// append a new one.
const List<String> sqliteMigrations = [
  '''
  CREATE TABLE exercises (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE routines (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE routine_exercises (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE schedule (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE sessions (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE exercise_logs (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE set_logs (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE decisions (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE links (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE goals (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE TABLE settings (id TEXT PRIMARY KEY, parent TEXT, parent2 TEXT, json TEXT NOT NULL);
  CREATE INDEX routine_exercises_routine ON routine_exercises(parent);
  CREATE INDEX exercise_logs_session ON exercise_logs(parent);
  CREATE INDEX exercise_logs_exercise ON exercise_logs(parent2);
  CREATE INDEX set_logs_log ON set_logs(parent);
  ''',
];

/// Ids are stored uppercase (Swift `uuidString`); lookups are case-insensitive like `UUID` ==.
String _k(String id) => id.toUpperCase();

class SqliteGymRepository extends GymRepository {
  /// File path, or null for an in-memory database (tests).
  final String? path;
  late final Database _db;

  final Map<String, Exercise> _exercises = {};
  final Map<String, RoutineTemplate> _routines = {};
  final Map<String, RoutineExercise> _routineExercises = {};
  final Map<String, ScheduleEntry> _schedule = {};
  final Map<String, WorkoutSession> _sessions = {};
  final Map<String, ExerciseLog> _logs = {};
  final Map<String, SetLog> _sets = {};

  /// Keyed by exercise log id (one decision per log).
  final Map<String, RecommendationDecision> _decisions = {};
  final Map<String, ComparabilityLink> _links = {};
  final Map<String, Goal> _goals = {};
  UserSettings _settings = UserSettings();

  // Secondary indexes (parent id → child ids).
  final Map<String, Set<String>> _logsBySession = {};
  final Map<String, Set<String>> _logsByExercise = {};
  final Map<String, Set<String>> _setsByLog = {};

  int _batchDepth = 0;
  int _savepoint = 0;
  int _writes = 0;

  /// Opens (and migrates) the database. Throws [GymStoreError] (`storage`) if some record can't be
  /// read, and `unsupportedSchemaVersion` for a database written by a newer app version.
  SqliteGymRepository.open([this.path]) {
    _db = path == null ? sqlite3.openInMemory() : sqlite3.open(path!);
    try {
      if (path != null) _db.execute('PRAGMA journal_mode = WAL');
      _db.execute('PRAGMA synchronous = FULL');
      _migrate();
      final corrupt = _loadAll();
      if (corrupt.isNotEmpty) {
        throw GymStoreError(GymStoreErrorKind.storage, 'Registros ilegibles: ${corrupt.join(', ')}');
      }
    } catch (e) {
      _db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  int get schemaVersion => _db.select('PRAGMA user_version').first.values.first as int;

  void _migrate() {
    final version = schemaVersion;
    if (version > sqliteMigrations.length) {
      throw GymStoreError(GymStoreErrorKind.unsupportedSchemaVersion, '$version');
    }
    for (var v = version; v < sqliteMigrations.length; v++) {
      _db.execute('BEGIN IMMEDIATE');
      try {
        _db.execute(sqliteMigrations[v]);
        _db.execute('PRAGMA user_version = ${v + 1}');
        _db.execute('COMMIT');
      } catch (e) {
        _db.execute('ROLLBACK');
        throw GymStoreError(GymStoreErrorKind.storage, 'migration ${v + 1}: $e');
      }
    }
  }

  // MARK: Loading

  void _clear() {
    for (final m in [
      _exercises,
      _routines,
      _routineExercises,
      _schedule,
      _sessions,
      _logs,
      _sets,
      _decisions,
      _links,
      _goals,
    ]) {
      m.clear();
    }
    _logsBySession.clear();
    _logsByExercise.clear();
    _setsByLog.clear();
    _settings = UserSettings();
  }

  /// Loads every record; returns the rows that could not be decoded.
  List<String> _loadAll() {
    _clear();
    final corrupt = <String>[];
    void load<T>(String table, T Function(Json) decode, void Function(T) put) {
      for (final row in _db.select('SELECT id, json FROM $table')) {
        try {
          put(decode(asJson(jsonDecode(row['json'] as String))));
        } catch (e) {
          corrupt.add('$table/${row['id']}');
        }
      }
    }

    load('exercises', Exercise.fromJson, (Exercise e) => _exercises[e.id] = e);
    load('routines', RoutineTemplate.fromJson, (RoutineTemplate r) => _routines[r.id] = r);
    load('routine_exercises', RoutineExercise.fromJson, (RoutineExercise r) => _routineExercises[r.id] = r);
    load('schedule', ScheduleEntry.fromJson, (ScheduleEntry e) => _schedule[e.id] = e);
    load('sessions', WorkoutSession.fromJson, (WorkoutSession s) => _sessions[s.id] = s);
    load('exercise_logs', ExerciseLog.fromJson, _putLog);
    load('set_logs', SetLog.fromJson, _putSet);
    load('decisions', RecommendationDecision.fromJson, (RecommendationDecision d) => _decisions[d.exerciseLogId] = d);
    load('links', ComparabilityLink.fromJson, (ComparabilityLink l) => _links[l.id] = l);
    load('goals', Goal.fromJson, (Goal g) => _goals[g.id] = g);
    load('settings', UserSettings.fromJson, (UserSettings s) => _settings = s);
    return corrupt;
  }

  // MARK: Writing

  static _Op _upsert(String table, String id, Json json, [String? parent, String? parent2]) =>
      _Op('INSERT OR REPLACE INTO $table (id, parent, parent2, json) VALUES (?, ?, ?, ?)', [id, parent, parent2], json);

  static _Op _delete(String table, String id) => _Op('DELETE FROM $table WHERE id = ?', [id]);

  /// Writes `ops` atomically, then applies `change` to memory (only after the write succeeded).
  /// Outside a batch: one transaction. Inside a batch: one savepoint, so a failed multi-statement
  /// mutation never leaves half of it in the database even if the caller catches the error.
  void _mutate(List<_Op> ops, void Function() change) {
    final nested = _batchDepth > 0;
    final sp = 'm${_savepoint++}';
    _db.execute(nested ? 'SAVEPOINT $sp' : 'BEGIN IMMEDIATE');
    try {
      _exec(ops);
      _db.execute(nested ? 'RELEASE $sp' : 'COMMIT');
      _writes++;
    } catch (e) {
      try {
        _db.execute(nested ? 'ROLLBACK TO $sp' : 'ROLLBACK');
        if (nested) _db.execute('RELEASE $sp');
      } catch (_) {}
      throw GymStoreError(GymStoreErrorKind.storage, '$e');
    }
    change();
  }

  void _exec(List<_Op> ops) {
    for (final op in ops) {
      _db.execute(op.sql, op.json == null ? op.params : [...op.params, jsonEncode(op.json)]);
    }
  }

  /// Groups many writes into one atomic unit (service calls, seeding, imports). On error the
  /// database rolls back (to the enclosing savepoint when nested) and memory is reloaded from it.
  T batch<T>(T Function() body) {
    final nested = _batchDepth > 0;
    final sp = 'b${_savepoint++}';
    _db.execute(nested ? 'SAVEPOINT $sp' : 'BEGIN IMMEDIATE');
    _batchDepth++;
    final writesBefore = _writes;
    try {
      final result = body();
      _db.execute(nested ? 'RELEASE $sp' : 'COMMIT');
      return result;
    } catch (e) {
      try {
        _db.execute(nested ? 'ROLLBACK TO $sp' : 'ROLLBACK');
        if (nested) _db.execute('RELEASE $sp');
      } catch (_) {}
      // Memory only differs from the database if something was written in this batch.
      if (_writes != writesBefore) _loadAll();
      if (e is GymStoreError) rethrow;
      throw GymStoreError(GymStoreErrorKind.storage, '$e');
    } finally {
      _batchDepth--;
    }
  }

  @override
  T transaction<T>(T Function() body) => batch(body);

  // MARK: Catalog

  @override
  List<Exercise> exercises() => stableSorted(_exercises.values, (a, b) {
    final c = compareNames(a.name, b.name);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((e) => e.copy()).toList();

  @override
  Exercise? exercise(String id) => _exercises[_k(id)]?.copy();

  @override
  void upsertExercise(Exercise exercise) {
    final e = exercise.copy();
    _mutate([_upsert('exercises', e.id, e.toJson())], () => _exercises[e.id] = e);
  }

  @override
  void deleteExercise(String id) {
    if (hasExerciseHistory(id)) throw const GymStoreError(GymStoreErrorKind.hasHistory);
    final key = _k(id);
    final items = _routineExercises.values.where((r) => _k(r.exerciseId) == key).map((r) => r.id).toList();
    _mutate([_delete('exercises', key), for (final i in items) _delete('routine_exercises', i)], () {
      _exercises.remove(key);
      items.forEach(_routineExercises.remove);
    });
  }

  // MARK: Routines

  @override
  List<RoutineTemplate> routines() => stableSorted(_routines.values, (a, b) {
    if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((r) => r.copy()).toList();

  @override
  RoutineTemplate? routine(String id) => _routines[_k(id)]?.copy();

  @override
  void upsertRoutine(RoutineTemplate routine) {
    final r = routine.copy();
    _mutate([_upsert('routines', r.id, r.toJson())], () => _routines[r.id] = r);
  }

  @override
  void deleteRoutine(String id) {
    if (hasRoutineHistory(id)) throw const GymStoreError(GymStoreErrorKind.hasHistory);
    final key = _k(id);
    final items = _routineExercises.values.where((r) => _k(r.routineId) == key).map((r) => r.id).toList();
    _mutate([_delete('routines', key), for (final i in items) _delete('routine_exercises', i)], () {
      _routines.remove(key);
      items.forEach(_routineExercises.remove);
    });
  }

  @override
  List<RoutineExercise> routineExercises(String routineId) => stableSorted(
    _routineExercises.values.where((r) => _k(r.routineId) == _k(routineId)),
    (a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id),
  ).map((r) => r.copy()).toList();

  @override
  RoutineExercise? routineExercise(String id) => _routineExercises[_k(id)]?.copy();

  @override
  void upsertRoutineExercise(RoutineExercise item) {
    final r = item.copy();
    _mutate([_upsert('routine_exercises', r.id, r.toJson(), r.routineId)], () => _routineExercises[r.id] = r);
  }

  @override
  void deleteRoutineExercise(String id) =>
      _mutate([_delete('routine_exercises', _k(id))], () => _routineExercises.remove(_k(id)));

  // MARK: Schedule

  @override
  List<ScheduleEntry> scheduleEntries() => stableSorted(_schedule.values, (a, b) {
    var c = a.validFrom.compareTo(b.validFrom);
    if (c != 0) return c;
    c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((e) => ScheduleEntry.fromJson(e.toJson())).toList();

  @override
  void insertScheduleEntry(ScheduleEntry entry) {
    if (_schedule.containsKey(_k(entry.id))) {
      throw const GymStoreError.invalidValue('El calendario no se reescribe: se agregan entradas nuevas.');
    }
    final e = ScheduleEntry.fromJson(entry.toJson());
    _mutate([_upsert('schedule', e.id, e.toJson())], () => _schedule[e.id] = e);
  }

  // MARK: History

  @override
  List<WorkoutSession> sessions() => stableSorted(_sessions.values, (a, b) {
    final c = a.startedAt.compareTo(b.startedAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((s) => s.copy()).toList();

  @override
  WorkoutSession? session(String id) => _sessions[_k(id)]?.copy();

  @override
  void upsertSession(WorkoutSession session) {
    final s = session.copy();
    _mutate([_upsert('sessions', s.id, s.toJson())], () => _sessions[s.id] = s);
  }

  @override
  List<ExerciseLog> exerciseLogsOfSession(String sessionId) => stableSorted(
    (_logsBySession[_k(sessionId)] ?? const <String>{}).map((id) => _logs[id]).whereType<ExerciseLog>(),
    (a, b) => a.plannedOrder != b.plannedOrder ? a.plannedOrder.compareTo(b.plannedOrder) : a.id.compareTo(b.id),
  ).map((l) => l.copy()).toList();

  @override
  List<ExerciseLog> exerciseLogsOfExercise(String exerciseId) => stableSorted(
    (_logsByExercise[_k(exerciseId)] ?? const <String>{}).map((id) => _logs[id]).whereType<ExerciseLog>(),
    (a, b) => a.id.compareTo(b.id),
  ).map((l) => l.copy()).toList();

  @override
  ExerciseLog? exerciseLog(String id) => _logs[_k(id)]?.copy();

  @override
  void upsertExerciseLog(ExerciseLog log) {
    final l = log.copy();
    _mutate([_upsert('exercise_logs', l.id, l.toJson(), l.sessionId, l.exerciseId)], () => _putLog(l));
  }

  @override
  void deleteExerciseLog(String id) {
    final key = _k(id);
    final sets = List.of(_setsByLog[key] ?? const <String>{});
    final decision = _decisions[key];
    _mutate(
      [
        for (final s in sets) _delete('set_logs', s),
        _delete('exercise_logs', key),
        if (decision != null) _delete('decisions', decision.exerciseLogId),
      ],
      () {
        sets.forEach(_removeSet);
        _removeLog(key);
        _decisions.remove(key);
      },
    );
  }

  @override
  List<SetLog> setLogs(String exerciseLogId) => stableSorted(
    (_setsByLog[_k(exerciseLogId)] ?? const <String>{}).map((id) => _sets[id]).whereType<SetLog>(),
    (a, b) => a.index != b.index ? a.index.compareTo(b.index) : a.id.compareTo(b.id),
  ).map((s) => s.copy()).toList();

  @override
  SetLog? setLog(String id) => _sets[_k(id)]?.copy();

  @override
  void upsertSetLog(SetLog set) {
    final s = set.copy();
    _mutate([_upsert('set_logs', s.id, s.toJson(), s.exerciseLogId)], () => _putSet(s));
  }

  @override
  void deleteSetLog(String id) => _mutate([_delete('set_logs', _k(id))], () => _removeSet(_k(id)));

  void _putLog(ExerciseLog log) {
    _removeLog(log.id);
    _logs[log.id] = log;
    _logsBySession.putIfAbsent(_k(log.sessionId), () => {}).add(log.id);
    _logsByExercise.putIfAbsent(_k(log.exerciseId), () => {}).add(log.id);
  }

  void _removeLog(String id) {
    final old = _logs.remove(id);
    if (old == null) return;
    _logsBySession[_k(old.sessionId)]?.remove(id);
    _logsByExercise[_k(old.exerciseId)]?.remove(id);
  }

  void _putSet(SetLog set) {
    _removeSet(set.id);
    _sets[set.id] = set;
    _setsByLog.putIfAbsent(_k(set.exerciseLogId), () => {}).add(set.id);
  }

  void _removeSet(String id) {
    final old = _sets.remove(id);
    if (old == null) return;
    _setsByLog[_k(old.exerciseLogId)]?.remove(id);
  }

  @override
  RecommendationDecision? decision(String exerciseLogId) {
    final d = _decisions[_k(exerciseLogId)];
    return d == null ? null : RecommendationDecision.fromJson(d.toJson());
  }

  @override
  void upsertDecision(RecommendationDecision decision) {
    final d = RecommendationDecision.fromJson(decision.toJson());
    // One decision per exercise log: keyed by the log id, like Swift.
    _mutate([_upsert('decisions', d.exerciseLogId, d.toJson(), d.id)], () => _decisions[d.exerciseLogId] = d);
  }

  // MARK: Links, goals, settings

  @override
  List<ComparabilityLink> comparabilityLinks() => stableSorted(_links.values, (a, b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((l) => ComparabilityLink.fromJson(l.toJson())).toList();

  @override
  void insertComparabilityLink(ComparabilityLink link) {
    final l = ComparabilityLink.fromJson(link.toJson());
    _mutate([_upsert('links', l.id, l.toJson())], () => _links[l.id] = l);
  }

  @override
  void deleteComparabilityLink(String id) => _mutate([_delete('links', _k(id))], () => _links.remove(_k(id)));

  @override
  List<Goal> goals() => stableSorted(_goals.values, (a, b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }).map((g) => g.copy()).toList();

  @override
  void upsertGoal(Goal goal) {
    final g = goal.copy();
    _mutate([_upsert('goals', g.id, g.toJson())], () => _goals[g.id] = g);
  }

  @override
  void deleteGoal(String id) => _mutate([_delete('goals', _k(id))], () => _goals.remove(_k(id)));

  @override
  UserSettings settings() => _settings.copy();

  @override
  void saveSettings(UserSettings settings) {
    final s = settings.copy();
    _mutate([_upsert('settings', 'settings', s.toJson())], () => _settings = s);
  }

  // MARK: Snapshot and merge

  @override
  GymDatabase snapshot() {
    List<T> byId<T>(Iterable<T> values, String Function(T) id, T Function(T) copy) =>
        stableSorted(values, (T a, T b) => id(a).compareTo(id(b))).map(copy).toList();
    return GymDatabase(
      exercises: exercises(),
      routines: routines(),
      routineExercises: byId(_routineExercises.values, (r) => r.id, (r) => r.copy()),
      schedule: scheduleEntries(),
      sessions: sessions(),
      exerciseLogs: byId(_logs.values, (l) => l.id, (l) => l.copy()),
      setLogs: byId(_sets.values, (s) => s.id, (s) => s.copy()),
      decisions: byId(_decisions.values, (d) => d.id, (d) => RecommendationDecision.fromJson(d.toJson())),
      comparabilityLinks: comparabilityLinks(),
      goals: goals(),
      settings: settings(),
    );
  }

  @override
  void merge(GymDatabase database, {required bool includeSettings}) {
    final exercises = database.exercises.where((e) => !_exercises.containsKey(_k(e.id))).toList();
    final routines = database.routines.where((r) => !_routines.containsKey(_k(r.id))).toList();
    final items = database.routineExercises.where((r) => !_routineExercises.containsKey(_k(r.id))).toList();
    final schedule = database.schedule.where((e) => !_schedule.containsKey(_k(e.id))).toList();
    final sessions = database.sessions.where((s) => !_sessions.containsKey(_k(s.id))).toList();
    final logs = database.exerciseLogs.where((l) => !_logs.containsKey(_k(l.id))).toList();
    final sets = database.setLogs.where((s) => !_sets.containsKey(_k(s.id))).toList();
    final decisions = database.decisions.where((d) => !_decisions.containsKey(_k(d.exerciseLogId))).toList();
    final links = database.comparabilityLinks.where((l) => !_links.containsKey(_k(l.id))).toList();
    final goals = database.goals.where((g) => !_goals.containsKey(_k(g.id))).toList();
    batch(() {
      exercises.forEach(upsertExercise);
      routines.forEach(upsertRoutine);
      items.forEach(upsertRoutineExercise);
      for (final e in schedule) {
        final copy = ScheduleEntry.fromJson(e.toJson());
        _mutate([_upsert('schedule', copy.id, copy.toJson())], () => _schedule[copy.id] = copy);
      }
      sessions.forEach(upsertSession);
      logs.forEach(upsertExerciseLog);
      sets.forEach(upsertSetLog);
      decisions.forEach(upsertDecision);
      links.forEach(insertComparabilityLink);
      goals.forEach(upsertGoal);
      if (includeSettings) saveSettings(database.settings);
    });
  }
}
