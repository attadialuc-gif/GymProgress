/// Storage abstraction (port of GymRepository.swift). Services depend only on this interface.
/// Every mutating call persists immediately (incremental save: a crash never loses a completed set).
/// Reads return copies (Swift value semantics): mutating a returned record never changes the store
/// until it is upserted.
library;

import 'package:gym_core/gym_core.dart';

import 'records.dart';

abstract class GymRepository {
  // Catalog
  List<Exercise> exercises();
  Exercise? exercise(String id);
  void upsertExercise(Exercise exercise);
  void deleteExercise(String id);

  // Routines
  List<RoutineTemplate> routines();
  RoutineTemplate? routine(String id);
  void upsertRoutine(RoutineTemplate routine);
  void deleteRoutine(String id);
  List<RoutineExercise> routineExercises(String routineId);
  RoutineExercise? routineExercise(String id);
  void upsertRoutineExercise(RoutineExercise item);
  void deleteRoutineExercise(String id);

  // Schedule (append-only)
  List<ScheduleEntry> scheduleEntries();
  void insertScheduleEntry(ScheduleEntry entry);

  // History
  List<WorkoutSession> sessions();
  WorkoutSession? session(String id);
  void upsertSession(WorkoutSession session);
  List<ExerciseLog> exerciseLogsOfSession(String sessionId);
  List<ExerciseLog> exerciseLogsOfExercise(String exerciseId);
  ExerciseLog? exerciseLog(String id);
  void upsertExerciseLog(ExerciseLog log);
  void deleteExerciseLog(String id);
  List<SetLog> setLogs(String exerciseLogId);
  SetLog? setLog(String id);
  void upsertSetLog(SetLog set);
  void deleteSetLog(String id);
  RecommendationDecision? decision(String exerciseLogId);
  void upsertDecision(RecommendationDecision decision);

  // Comparability, goals, settings
  List<ComparabilityLink> comparabilityLinks();
  void insertComparabilityLink(ComparabilityLink link);
  void deleteComparabilityLink(String id);
  List<Goal> goals();
  void upsertGoal(Goal goal);
  void deleteGoal(String id);
  UserSettings settings();
  void saveSettings(UserSettings settings);

  /// Full snapshot (export / backup).
  GymDatabase snapshot();

  /// Inserts the records of `database` whose ids do not exist yet; never overwrites or deletes
  /// existing records. All-or-nothing.
  void merge(GymDatabase database, {required bool includeSettings});

  /// Throws if some stored record cannot be read (an export must never be silently incomplete).
  void validateIntegrity() {}

  /// Runs `body` atomically: every write inside commits together or none does (service calls).
  T transaction<T>(T Function() body) => body();

  // Batched reads (implementations may override for efficiency).
  Map<String, List<SetLog>> setLogsOfLogs(List<String> exerciseLogIds) => {
    for (final id in exerciseLogIds) id: setLogs(id),
  };

  Map<String, WorkoutSession> sessionsById(Iterable<String> ids) {
    final result = <String, WorkoutSession>{};
    for (final id in ids) {
      final s = session(id);
      if (s != null) result[id] = s;
    }
    return result;
  }

  /// All sets of a session, grouped by log.
  Map<String, List<SetLog>> setLogsOfSession(String sessionId) => {
    for (final log in exerciseLogsOfSession(sessionId)) log.id: setLogs(log.id),
  };

  bool hasExerciseHistory(String exerciseId) => exerciseLogsOfExercise(exerciseId).isNotEmpty;

  bool hasRoutineHistory(String routineId) => sessions().any((s) => s.routineId == routineId);
}

/// Name order like Foundation `localizedCompare` (ICU collation): letters compared without accents
/// or case first, then accents, then lower case before upper case; spaces and punctuation before
/// digits, digits before letters.
int compareNames(String a, String b) {
  // Decomposed ñ (n + U+0303) is the same letter as precomposed ñ.
  a = a.replaceAll('n\u0303', 'ñ').replaceAll('N\u0303', 'Ñ');
  b = b.replaceAll('n\u0303', 'ñ').replaceAll('N\u0303', 'Ñ');
  for (final level in [_primary, _secondary, _tertiary]) {
    final ka = level(a), kb = level(b);
    final n = ka.length < kb.length ? ka.length : kb.length;
    for (var i = 0; i < n; i++) {
      if (ka[i] != kb[i]) return ka[i] < kb[i] ? -1 : 1;
    }
    if (ka.length != kb.length) return ka.length < kb.length ? -1 : 1;
  }
  return 0;
}

const String _punctuationOrder = '_-,;:!?.\'"()[]{}@*/\\&#%`^+<=>|~\$';

List<int> _primary(String s) => [
  for (final r in _foldKeepingEnye(s))
    if (r == _enyeKey)
      1000 + 2 * 0x6E + 1
    else if (isSwiftWhitespace(r))
      10
    else if (_punctuationOrder.contains(String.fromCharCode(r)))
      100 + _punctuationOrder.indexOf(String.fromCharCode(r))
    else if (r >= 0x30 && r <= 0x39)
      500 + r
    else if (r >= 0x61 && r <= 0x7A)
      1000 + 2 * r
    else
      2000 + r,
];

List<int> _secondary(String s) => [
  for (final r in s.toLowerCase().runes) foldDiacritics(String.fromCharCode(r)) == String.fromCharCode(r) ? 0 : r,
];

List<int> _tertiary(String s) => [
  for (final r in s.runes) String.fromCharCode(r).toLowerCase() == String.fromCharCode(r) ? 0 : 1,
];

const int _enyeKey = -1;

/// Folded runes where ñ/Ñ (precomposed or n + U+0303) stay distinct from n.
List<int> _foldKeepingEnye(String s) {
  final runes = s.runes.toList();
  final out = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final decomposedEnye = (r == 0x6E || r == 0x4E) && i + 1 < runes.length && runes[i + 1] == 0x303;
    if (r == 0xF1 || r == 0xD1 || decomposedEnye) {
      out.add(_enyeKey);
      if (decomposedEnye) i++;
      continue;
    }
    out.addAll(foldDiacritics(String.fromCharCode(r)).runes);
  }
  return out;
}
