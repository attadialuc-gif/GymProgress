/// Persistable records (port of GymStore/Records.swift). Same JSON as Swift `Codable`, so a
/// GymProgress export from iPhone imports here and vice versa (schemaVersion contract).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:gym_core/gym_core.dart';

/// Version of the persisted/exported data schema (Swift `GymSchema.currentVersion`).
const int gymSchemaVersion = 1;

final math.Random _random = math.Random.secure();

/// Random (v4) UUID, uppercase like Swift's `uuidString`.
String newUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Canonical JSON (sorted keys) used for record equality (Swift `Hashable` ==).
String canonicalJson(Object? value) => jsonEncode(_sortKeys(value));

Object? _sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    return {for (final k in keys) k: _sortKeys(v[k])};
  }
  if (v is List) return v.map(_sortKeys).toList();
  return v;
}

/// Swift `Date` interval `[start, end)`.
class DateInterval {
  final DateTime start;
  final DateTime end;
  const DateInterval(this.start, this.end);

  /// Periods never count an instant twice at their boundary.
  bool containsHalfOpen(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateInterval && other.start.compareTo(start) == 0 && other.end.compareTo(end) == 0;

  @override
  int get hashCode => Object.hash(start.microsecondsSinceEpoch, end.microsecondsSinceEpoch);
}

class RoutineTemplate {
  String id;
  String name;
  int sortOrder;
  String notes;
  bool isArchived;
  DateTime createdAt;

  RoutineTemplate({
    String? id,
    required this.name,
    this.sortOrder = 0,
    this.notes = '',
    this.isArchived = false,
    required this.createdAt,
  }) : id = id ?? newUuid();

  RoutineTemplate copy() => RoutineTemplate.fromJson(toJson());

  factory RoutineTemplate.fromJson(Json j) => RoutineTemplate(
    id: uuidFromJson(j['id']),
    name: j['name'] as String,
    sortOrder: toInt(j['sortOrder']),
    notes: j['notes'] as String,
    isArchived: j['isArchived'] as bool,
    createdAt: dateFromJson(j['createdAt']),
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'sortOrder': sortOrder,
    'notes': notes,
    'isArchived': isArchived,
    'createdAt': dateToJson(createdAt),
  };
}

class RoutineExercise {
  String id;
  String routineId;
  String exerciseId;
  int sortOrder;

  /// Exercises sharing a group number are performed as a superset / biset.
  int? supersetGroup;
  int? restSeconds;
  String notes;

  /// Per-routine override of the exercise's progression criteria.
  ProgressionConfig? progressionOverride;

  RoutineExercise({
    String? id,
    required this.routineId,
    required this.exerciseId,
    required this.sortOrder,
    this.supersetGroup,
    this.restSeconds,
    this.notes = '',
    this.progressionOverride,
  }) : id = id ?? newUuid();

  RoutineExercise copy() => RoutineExercise.fromJson(toJson());

  factory RoutineExercise.fromJson(Json j) => RoutineExercise(
    id: uuidFromJson(j['id']),
    routineId: uuidFromJson(j['routineId']),
    exerciseId: uuidFromJson(j['exerciseId']),
    sortOrder: toInt(j['sortOrder']),
    supersetGroup: optInt(j['supersetGroup']),
    restSeconds: optInt(j['restSeconds']),
    notes: j['notes'] as String,
    progressionOverride: j['progressionOverride'] == null
        ? null
        : ProgressionConfig.fromJson(asJson(j['progressionOverride'])),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'routineId': routineId,
      'exerciseId': exerciseId,
      'sortOrder': sortOrder,
      'notes': notes,
    };
    putOpt(j, 'supersetGroup', supersetGroup);
    putOpt(j, 'restSeconds', restSeconds);
    putOpt(j, 'progressionOverride', progressionOverride?.toJson());
    return j;
  }
}

class PauseInterval {
  DateTime start;
  DateTime? end;
  PauseInterval(this.start, [this.end]);

  factory PauseInterval.fromJson(Json j) => PauseInterval(dateFromJson(j['start']), optDate(j['end']));

  Json toJson() {
    final j = <String, Object?>{'start': dateToJson(start)};
    putOpt(j, 'end', end == null ? null : dateToJson(end!));
    return j;
  }
}

class WorkoutSession {
  String id;
  String? routineId;

  /// Routine name at the time of the session (history never depends on the template).
  String? routineNameSnapshot;
  DateTime startedAt;
  DateTime? endedAt;
  List<PauseInterval> pauses;
  SessionStatus status;
  String notes;

  /// Illness, deload, travel…: shown, but excluded from trends and recommendations.
  bool isAtypical;
  DateTime updatedAt;

  WorkoutSession({
    String? id,
    this.routineId,
    this.routineNameSnapshot,
    required this.startedAt,
    this.endedAt,
    List<PauseInterval>? pauses,
    this.status = SessionStatus.active,
    this.notes = '',
    this.isAtypical = false,
    required this.updatedAt,
  }) : id = id ?? newUuid(),
       pauses = pauses ?? [];

  WorkoutSession copy() => WorkoutSession.fromJson(toJson());

  /// Elapsed training time in seconds, excluding pauses. Timestamp-based (survives app suspension
  /// and process death).
  double elapsed(DateTime now) {
    final end = endedAt ?? now;
    var paused = 0.0;
    for (final p in pauses) {
      final pEnd0 = p.end ?? end;
      final pEnd = pEnd0.isBefore(end) ? pEnd0 : end;
      final d = _seconds(pEnd, p.start);
      paused += d > 0 ? d : 0;
    }
    final total = _seconds(end, startedAt) - paused;
    return total > 0 ? total : 0;
  }

  static double _seconds(DateTime a, DateTime b) => (a.microsecondsSinceEpoch - b.microsecondsSinceEpoch) / 1e6;

  bool get isOpen => status == SessionStatus.active || status == SessionStatus.paused;

  factory WorkoutSession.fromJson(Json j) => WorkoutSession(
    id: uuidFromJson(j['id']),
    routineId: optUuid(j['routineId']),
    routineNameSnapshot: j['routineNameSnapshot'] as String?,
    startedAt: dateFromJson(j['startedAt']),
    endedAt: optDate(j['endedAt']),
    pauses: listOf(j['pauses'] ?? (throw const FormatException('pauses')), (e) => PauseInterval.fromJson(asJson(e))),
    status: enumFromName(SessionStatus.values, j['status']),
    notes: j['notes'] as String,
    isAtypical: j['isAtypical'] as bool,
    updatedAt: dateFromJson(j['updatedAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'startedAt': dateToJson(startedAt),
      'pauses': pauses.map((p) => p.toJson()).toList(),
      'status': status.name,
      'notes': notes,
      'isAtypical': isAtypical,
      'updatedAt': dateToJson(updatedAt),
    };
    putOpt(j, 'routineId', routineId);
    putOpt(j, 'routineNameSnapshot', routineNameSnapshot);
    putOpt(j, 'endedAt', endedAt == null ? null : dateToJson(endedAt!));
    return j;
  }
}

/// One exercise inside a session, with snapshots, context and the recommendation frozen when it
/// was first opened (audit of what was shown).
class ExerciseLog {
  String id;
  String sessionId;
  String exerciseId;
  String? routineExerciseId;
  int? supersetGroup;
  ExerciseSnapshot snapshot;

  /// Effective progression config at session start (routine override ?? exercise config).
  ProgressionConfig configSnapshot;
  String? variantLabel;
  String? equipmentLabel;
  int plannedOrder;

  /// Real execution order: assigned when the first set of this exercise is completed.
  int? executionOrder;
  int? restSeconds;
  String notes;
  bool isAtypical;
  Recommendation? frozenRecommendation;
  DateTime? recommendationFrozenAt;

  ExerciseLog({
    String? id,
    required this.sessionId,
    required this.exerciseId,
    this.routineExerciseId,
    this.supersetGroup,
    required this.snapshot,
    required this.configSnapshot,
    this.variantLabel,
    this.equipmentLabel,
    required this.plannedOrder,
    this.executionOrder,
    this.restSeconds,
    this.notes = '',
    this.isAtypical = false,
    this.frozenRecommendation,
    this.recommendationFrozenAt,
  }) : id = id ?? newUuid();

  ExerciseLog copy() => ExerciseLog.fromJson(toJson());

  ComparabilityContext get context => ComparabilityContext(
    exerciseId: exerciseId,
    variantLabel: variantLabel,
    equipmentLabel: equipmentLabel,
    loadMode: snapshot.loadMode,
  );

  factory ExerciseLog.fromJson(Json j) => ExerciseLog(
    id: uuidFromJson(j['id']),
    sessionId: uuidFromJson(j['sessionId']),
    exerciseId: uuidFromJson(j['exerciseId']),
    routineExerciseId: optUuid(j['routineExerciseId']),
    supersetGroup: optInt(j['supersetGroup']),
    snapshot: ExerciseSnapshot.fromJson(asJson(j['snapshot'])),
    configSnapshot: ProgressionConfig.fromJson(asJson(j['configSnapshot'])),
    variantLabel: j['variantLabel'] as String?,
    equipmentLabel: j['equipmentLabel'] as String?,
    plannedOrder: toInt(j['plannedOrder']),
    executionOrder: optInt(j['executionOrder']),
    restSeconds: optInt(j['restSeconds']),
    notes: j['notes'] as String,
    isAtypical: j['isAtypical'] as bool,
    frozenRecommendation: j['frozenRecommendation'] == null
        ? null
        : Recommendation.fromJson(asJson(j['frozenRecommendation'])),
    recommendationFrozenAt: optDate(j['recommendationFrozenAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'sessionId': sessionId,
      'exerciseId': exerciseId,
      'snapshot': snapshot.toJson(),
      'configSnapshot': configSnapshot.toJson(),
      'plannedOrder': plannedOrder,
      'notes': notes,
      'isAtypical': isAtypical,
    };
    putOpt(j, 'routineExerciseId', routineExerciseId);
    putOpt(j, 'supersetGroup', supersetGroup);
    putOpt(j, 'variantLabel', variantLabel);
    putOpt(j, 'equipmentLabel', equipmentLabel);
    putOpt(j, 'executionOrder', executionOrder);
    putOpt(j, 'restSeconds', restSeconds);
    putOpt(j, 'frozenRecommendation', frozenRecommendation?.toJson());
    putOpt(j, 'recommendationFrozenAt', recommendationFrozenAt == null ? null : dateToJson(recommendationFrozenAt!));
    return j;
  }
}

class SetLog {
  String id;
  String exerciseLogId;
  int index;
  SetKind kind;
  SetStatus status;
  double? weight;
  int? reps;
  int? seconds;
  double? addedWeight;
  double? assistance;
  double? rir;
  double? rpe;
  DateTime? completedAt;
  bool excludedFromEstimates;

  /// Reference shown next to the input (accepted/modified recommendation or copied loads).
  int? targetReps;
  int? targetSeconds;

  SetLog({
    String? id,
    required this.exerciseLogId,
    required this.index,
    this.kind = SetKind.working,
    this.status = SetStatus.pending,
    this.weight,
    this.reps,
    this.seconds,
    this.addedWeight,
    this.assistance,
    this.rir,
    this.rpe,
    this.completedAt,
    this.excludedFromEstimates = false,
    this.targetReps,
    this.targetSeconds,
  }) : id = id ?? newUuid();

  SetLog copy() => SetLog.fromJson(toJson());

  PerformedSet get performed => PerformedSet(
    index: index,
    kind: kind,
    status: status,
    weight: weight,
    reps: reps,
    seconds: seconds,
    addedWeight: addedWeight,
    assistance: assistance,
    rir: rir,
    rpe: rpe,
    completedAt: completedAt,
    excludedFromEstimates: excludedFromEstimates,
  );

  factory SetLog.fromJson(Json j) => SetLog(
    id: uuidFromJson(j['id']),
    exerciseLogId: uuidFromJson(j['exerciseLogId']),
    index: toInt(j['index']),
    kind: enumFromName(SetKind.values, j['kind']),
    status: enumFromName(SetStatus.values, j['status']),
    weight: optDouble(j['weight']),
    reps: optInt(j['reps']),
    seconds: optInt(j['seconds']),
    addedWeight: optDouble(j['addedWeight']),
    assistance: optDouble(j['assistance']),
    rir: optDouble(j['rir']),
    rpe: optDouble(j['rpe']),
    completedAt: optDate(j['completedAt']),
    excludedFromEstimates: j['excludedFromEstimates'] as bool,
    targetReps: optInt(j['targetReps']),
    targetSeconds: optInt(j['targetSeconds']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'exerciseLogId': exerciseLogId,
      'index': index,
      'kind': kind.name,
      'status': status.name,
      'excludedFromEstimates': excludedFromEstimates,
    };
    putOpt(j, 'weight', weight);
    putOpt(j, 'reps', reps);
    putOpt(j, 'seconds', seconds);
    putOpt(j, 'addedWeight', addedWeight);
    putOpt(j, 'assistance', assistance);
    putOpt(j, 'rir', rir);
    putOpt(j, 'rpe', rpe);
    putOpt(j, 'completedAt', completedAt == null ? null : dateToJson(completedAt!));
    putOpt(j, 'targetReps', targetReps);
    putOpt(j, 'targetSeconds', targetSeconds);
    return j;
  }
}

enum DecisionKind { accepted, modified, ignored }

/// The recommendation as shown to the user (kept inside the decision for audit).
class RecommendationSnapshot {
  final RecommendationAction action;
  final RecommendationReason reason;
  final RecommendationConfidence confidence;
  final double? targetWeight;
  final List<int> targetReps;
  final List<int>? targetSeconds;
  final String reasonText;

  const RecommendationSnapshot({
    required this.action,
    required this.reason,
    required this.confidence,
    this.targetWeight,
    required this.targetReps,
    this.targetSeconds,
    required this.reasonText,
  });

  factory RecommendationSnapshot.of(Recommendation r) => RecommendationSnapshot(
    action: r.action,
    reason: r.reason,
    confidence: r.confidence,
    targetWeight: r.targetWeight,
    targetReps: List.of(r.targetReps),
    targetSeconds: r.targetSeconds == null ? null : List.of(r.targetSeconds!),
    reasonText: r.reasonText,
  );

  factory RecommendationSnapshot.fromJson(Json j) => RecommendationSnapshot(
    action: enumFromName(RecommendationAction.values, j['action']),
    reason: enumFromName(RecommendationReason.values, j['reason']),
    confidence: enumFromName(RecommendationConfidence.values, j['confidence']),
    targetWeight: optDouble(j['targetWeight']),
    targetReps: listOf(j['targetReps'] ?? (throw const FormatException('targetReps')), toInt),
    targetSeconds: j['targetSeconds'] == null ? null : listOf(j['targetSeconds'], toInt),
    reasonText: j['reasonText'] as String,
  );

  Json toJson() {
    final j = <String, Object?>{
      'action': action.name,
      'reason': reason.name,
      'confidence': confidence.name,
      'targetReps': targetReps,
      'reasonText': reasonText,
    };
    putOpt(j, 'targetWeight', targetWeight);
    putOpt(j, 'targetSeconds', targetSeconds);
    return j;
  }
}

/// What the user chose. Source of truth for "today's target"; the engine never overwrites it.
class RecommendationDecision {
  String id;
  String exerciseLogId;
  RecommendationSnapshot recommended;
  DecisionKind kind;
  double? finalWeight;
  List<int> finalReps;
  List<int>? finalSeconds;
  DateTime decidedAt;

  RecommendationDecision({
    String? id,
    required this.exerciseLogId,
    required this.recommended,
    required this.kind,
    this.finalWeight,
    required this.finalReps,
    this.finalSeconds,
    required this.decidedAt,
  }) : id = id ?? newUuid();

  factory RecommendationDecision.fromJson(Json j) => RecommendationDecision(
    id: uuidFromJson(j['id']),
    exerciseLogId: uuidFromJson(j['exerciseLogId']),
    recommended: RecommendationSnapshot.fromJson(asJson(j['recommended'])),
    kind: enumFromName(DecisionKind.values, j['kind']),
    finalWeight: optDouble(j['finalWeight']),
    finalReps: listOf(j['finalReps'] ?? (throw const FormatException('finalReps')), toInt),
    finalSeconds: j['finalSeconds'] == null ? null : listOf(j['finalSeconds'], toInt),
    decidedAt: dateFromJson(j['decidedAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'exerciseLogId': exerciseLogId,
      'recommended': recommended.toJson(),
      'kind': kind.name,
      'finalReps': finalReps,
      'decidedAt': dateToJson(decidedAt),
    };
    putOpt(j, 'finalWeight', finalWeight);
    putOpt(j, 'finalSeconds', finalSeconds);
    return j;
  }
}

enum GoalMetric { weight, repsAtWeight, estimatedOneRepMax, sessionVolume }

enum GoalStatus { active, achieved, abandoned }

class Goal {
  String id;
  String exerciseId;
  GoalMetric metric;
  double value;

  /// For `repsAtWeight`: the load.
  double? weight;
  DateTime? targetDate;
  GoalStatus status;
  DateTime createdAt;
  DateTime? achievedAt;

  Goal({
    String? id,
    required this.exerciseId,
    required this.metric,
    required this.value,
    this.weight,
    this.targetDate,
    this.status = GoalStatus.active,
    required this.createdAt,
    this.achievedAt,
  }) : id = id ?? newUuid();

  Goal copy() => Goal.fromJson(toJson());

  factory Goal.fromJson(Json j) => Goal(
    id: uuidFromJson(j['id']),
    exerciseId: uuidFromJson(j['exerciseId']),
    metric: enumFromName(GoalMetric.values, j['metric']),
    value: toDouble(j['value']),
    weight: optDouble(j['weight']),
    targetDate: optDate(j['targetDate']),
    status: enumFromName(GoalStatus.values, j['status']),
    createdAt: dateFromJson(j['createdAt']),
    achievedAt: optDate(j['achievedAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'exerciseId': exerciseId,
      'metric': metric.name,
      'value': value,
      'status': status.name,
      'createdAt': dateToJson(createdAt),
    };
    putOpt(j, 'weight', weight);
    putOpt(j, 'targetDate', targetDate == null ? null : dateToJson(targetDate!));
    putOpt(j, 'achievedAt', achievedAt == null ? null : dateToJson(achievedAt!));
    return j;
  }
}

enum WeightUnit { kg, lb }

enum AppTheme { dark, light, system }

class UserSettings {
  /// Presentation only: data is always stored in kg.
  WeightUnit weightUnit;

  /// 1 = Sunday … 7 = Saturday. Default Monday.
  int firstWeekday;
  int defaultRestSeconds;
  AppTheme theme;
  int weeklyGoal;
  StreakMode streakMode;
  int maxGapDays;
  double indirectSetFactor;
  OneRepMaxSettings oneRepMax;
  int minSetsForValidSession;
  bool keepScreenOn;
  bool restNotifications;

  /// Optional: enables body-weight volume. null = unknown (never invented).
  double? bodyweightKg;

  /// Optional weekly direct-set goals per muscle (key = MuscleGroup name).
  Map<String, int>? muscleSetGoals;

  UserSettings({
    this.weightUnit = WeightUnit.kg,
    this.firstWeekday = 2,
    this.defaultRestSeconds = 120,
    this.theme = AppTheme.dark,
    this.weeklyGoal = 3,
    this.streakMode = StreakMode.weeklyPlan,
    this.maxGapDays = 2,
    this.indirectSetFactor = 0.5,
    this.oneRepMax = OneRepMaxSettings.standard,
    this.minSetsForValidSession = 3,
    this.keepScreenOn = true,
    this.restNotifications = true,
    this.bodyweightKg,
    this.muscleSetGoals,
  });

  UserSettings copy() => UserSettings.fromJson(toJson());

  int? weeklySetGoal(MuscleGroup muscle) => muscleSetGoals?[muscle.name];

  void setWeeklySetGoal(int? goal, MuscleGroup muscle) {
    final goals = Map<String, int>.of(muscleSetGoals ?? {});
    if (goal != null && goal > 0) {
      goals[muscle.name] = goal;
    } else {
      goals.remove(muscle.name);
    }
    muscleSetGoals = goals.isEmpty ? null : goals;
  }

  factory UserSettings.fromJson(Json j) => UserSettings(
    weightUnit: enumFromName(WeightUnit.values, j['weightUnit']),
    firstWeekday: toInt(j['firstWeekday']),
    defaultRestSeconds: toInt(j['defaultRestSeconds']),
    theme: enumFromName(AppTheme.values, j['theme']),
    weeklyGoal: toInt(j['weeklyGoal']),
    streakMode: enumFromName(StreakMode.values, j['streakMode']),
    maxGapDays: toInt(j['maxGapDays']),
    indirectSetFactor: toDouble(j['indirectSetFactor']),
    oneRepMax: OneRepMaxSettings.fromJson(asJson(j['oneRepMax'])),
    minSetsForValidSession: toInt(j['minSetsForValidSession']),
    keepScreenOn: j['keepScreenOn'] as bool,
    restNotifications: j['restNotifications'] as bool,
    bodyweightKg: optDouble(j['bodyweightKg']),
    muscleSetGoals: j['muscleSetGoals'] == null
        ? null
        : asJson(j['muscleSetGoals']).map((k, v) => MapEntry(k, toInt(v))),
  );

  Json toJson() {
    final j = <String, Object?>{
      'weightUnit': weightUnit.name,
      'firstWeekday': firstWeekday,
      'defaultRestSeconds': defaultRestSeconds,
      'theme': theme.name,
      'weeklyGoal': weeklyGoal,
      'streakMode': streakMode.name,
      'maxGapDays': maxGapDays,
      'indirectSetFactor': indirectSetFactor,
      'oneRepMax': oneRepMax.toJson(),
      'minSetsForValidSession': minSetsForValidSession,
      'keepScreenOn': keepScreenOn,
      'restNotifications': restNotifications,
    };
    putOpt(j, 'bodyweightKg', bodyweightKg);
    putOpt(j, 'muscleSetGoals', muscleSetGoals);
    return j;
  }
}

/// Whole database as one document: JSON store contract, export/import and backups.
class GymDatabase {
  int schemaVersion;
  DateTime? exportedAt;
  List<Exercise> exercises;
  List<RoutineTemplate> routines;
  List<RoutineExercise> routineExercises;
  List<ScheduleEntry> schedule;
  List<WorkoutSession> sessions;
  List<ExerciseLog> exerciseLogs;
  List<SetLog> setLogs;
  List<RecommendationDecision> decisions;
  List<ComparabilityLink> comparabilityLinks;
  List<Goal> goals;
  UserSettings settings;

  GymDatabase({
    this.schemaVersion = gymSchemaVersion,
    this.exportedAt,
    List<Exercise>? exercises,
    List<RoutineTemplate>? routines,
    List<RoutineExercise>? routineExercises,
    List<ScheduleEntry>? schedule,
    List<WorkoutSession>? sessions,
    List<ExerciseLog>? exerciseLogs,
    List<SetLog>? setLogs,
    List<RecommendationDecision>? decisions,
    List<ComparabilityLink>? comparabilityLinks,
    List<Goal>? goals,
    UserSettings? settings,
  }) : exercises = exercises ?? [],
       routines = routines ?? [],
       routineExercises = routineExercises ?? [],
       schedule = schedule ?? [],
       sessions = sessions ?? [],
       exerciseLogs = exerciseLogs ?? [],
       setLogs = setLogs ?? [],
       decisions = decisions ?? [],
       comparabilityLinks = comparabilityLinks ?? [],
       goals = goals ?? [],
       settings = settings ?? UserSettings();

  static List<T> _list<T>(Json j, String key, T Function(Json) f) {
    final v = j[key];
    if (v == null) throw FormatException('Missing $key');
    return (v as List).map((e) => f(asJson(e))).toList();
  }

  factory GymDatabase.fromJson(Json j) => GymDatabase(
    schemaVersion: toInt(j['schemaVersion']),
    exportedAt: optDate(j['exportedAt']),
    exercises: _list(j, 'exercises', Exercise.fromJson),
    routines: _list(j, 'routines', RoutineTemplate.fromJson),
    routineExercises: _list(j, 'routineExercises', RoutineExercise.fromJson),
    schedule: _list(j, 'schedule', ScheduleEntry.fromJson),
    sessions: _list(j, 'sessions', WorkoutSession.fromJson),
    exerciseLogs: _list(j, 'exerciseLogs', ExerciseLog.fromJson),
    setLogs: _list(j, 'setLogs', SetLog.fromJson),
    decisions: _list(j, 'decisions', RecommendationDecision.fromJson),
    comparabilityLinks: _list(j, 'comparabilityLinks', ComparabilityLink.fromJson),
    goals: _list(j, 'goals', Goal.fromJson),
    settings: UserSettings.fromJson(asJson(j['settings'] ?? (throw const FormatException('settings')))),
  );

  Json toJson() {
    final j = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exercises': exercises.map((e) => e.toJson()).toList(),
      'routines': routines.map((e) => e.toJson()).toList(),
      'routineExercises': routineExercises.map((e) => e.toJson()).toList(),
      'schedule': schedule.map((e) => e.toJson()).toList(),
      'sessions': sessions.map((e) => e.toJson()).toList(),
      'exerciseLogs': exerciseLogs.map((e) => e.toJson()).toList(),
      'setLogs': setLogs.map((e) => e.toJson()).toList(),
      'decisions': decisions.map((e) => e.toJson()).toList(),
      'comparabilityLinks': comparabilityLinks.map((e) => e.toJson()).toList(),
      'goals': goals.map((e) => e.toJson()).toList(),
      'settings': settings.toJson(),
    };
    putOpt(j, 'exportedAt', exportedAt == null ? null : dateToJson(exportedAt!));
    return j;
  }

  /// Same encoding as Swift `GymJSON.encoder`: sorted keys, pretty printed, dates as seconds.
  String encode() => const JsonEncoder.withIndent('  ').convert(_sortKeys(toJson()));
}

enum GymStoreErrorKind {
  notFound,
  sessionAlreadyOpen,
  sessionNotOpen,
  hasHistory,
  hasCompletedSets,
  missingValues,
  invalidValue,
  unsupportedSchemaVersion,
  invalidImport,
  storage,
}

/// Port of Swift `GymStoreError`. `message` holds the associated value (user-facing text when it
/// is one).
class GymStoreError implements Exception {
  final GymStoreErrorKind kind;
  final String? message;
  const GymStoreError(this.kind, [this.message]);

  const GymStoreError.notFound(String what) : this(GymStoreErrorKind.notFound, what);
  const GymStoreError.invalidValue(String text) : this(GymStoreErrorKind.invalidValue, text);
  const GymStoreError.invalidImport(String text) : this(GymStoreErrorKind.invalidImport, text);

  @override
  String toString() => 'GymStoreError.${kind.name}${message == null ? '' : '($message)'}';
}
