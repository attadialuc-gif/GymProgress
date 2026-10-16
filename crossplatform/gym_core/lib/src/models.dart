/// Domain models: ports of ProgressionConfig.swift, Comparability.swift, Exercise.swift and
/// Performance.swift with the same JSON shape as Swift `Codable`.
library;

import 'dart:convert';

import 'enums.dart';
import 'json_util.dart';
import 'load_math.dart';
import 'text.dart';

// MARK: - ProgressionConfig

enum ProgressionStrategyKind { doubleProgression }

class ProgressionConfig {
  ProgressionStrategyKind strategy;
  int targetSets;
  int repMin;
  int repMax;
  int? targetRIR;
  double? initialWeight;
  double increment;
  List<double>? availableWeights;
  int requiredConsecutiveSessions;
  int reassessAfterDays;
  int secondsMin;
  int secondsMax;
  int secondsIncrement;

  ProgressionConfig({
    this.strategy = ProgressionStrategyKind.doubleProgression,
    this.targetSets = 3,
    this.repMin = 8,
    this.repMax = 12,
    this.targetRIR = 2,
    this.initialWeight,
    this.increment = 2.5,
    this.availableWeights,
    this.requiredConsecutiveSessions = 1,
    this.reassessAfterDays = 21,
    this.secondsMin = 30,
    this.secondsMax = 60,
    this.secondsIncrement = 5,
  });

  ProgressionConfig copy() => ProgressionConfig.fromJson(toJson());

  /// Same clamping as Swift `sanitized()`.
  ProgressionConfig sanitized() {
    final c = copy();
    c.targetSets = _clamp(targetSets, 1, 20);
    c.repMin = _clamp(repMin, 1, 100);
    c.repMax = _max(c.repMin, _min(repMax, 100));
    if (targetRIR != null) c.targetRIR = _clamp(targetRIR!, 0, 10);
    final w = initialWeight;
    if (w != null && (!w.isFinite || w < 0)) c.initialWeight = null;
    c.increment = (increment.isFinite && increment > 0) ? increment : 2.5;
    if (availableWeights != null) {
      final set = <int, double>{};
      for (final x in availableWeights!) {
        if (x.isFinite && x >= 0) {
          final n = LoadMath.normalized(x);
          set[LoadMath.key(n)] = n;
        }
      }
      final list = set.values.toList()..sort();
      c.availableWeights = list.isEmpty ? null : list;
    }
    c.requiredConsecutiveSessions = _clamp(requiredConsecutiveSessions, 1, 10);
    c.reassessAfterDays = _max(1, reassessAfterDays);
    c.secondsMin = _max(1, secondsMin);
    c.secondsMax = _max(c.secondsMin, secondsMax);
    c.secondsIncrement = _max(1, secondsIncrement);
    return c;
  }

  static int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;

  factory ProgressionConfig.fromJson(Json j) => ProgressionConfig(
    strategy: enumFromName(ProgressionStrategyKind.values, j['strategy']),
    targetSets: toInt(j['targetSets']),
    repMin: toInt(j['repMin']),
    repMax: toInt(j['repMax']),
    targetRIR: optInt(j['targetRIR']),
    initialWeight: optDouble(j['initialWeight']),
    increment: toDouble(j['increment']),
    availableWeights: j['availableWeights'] == null ? null : listOf(j['availableWeights'], toDouble),
    requiredConsecutiveSessions: toInt(j['requiredConsecutiveSessions']),
    reassessAfterDays: toInt(j['reassessAfterDays']),
    secondsMin: toInt(j['secondsMin']),
    secondsMax: toInt(j['secondsMax']),
    secondsIncrement: toInt(j['secondsIncrement']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'strategy': strategy.name,
      'targetSets': targetSets,
      'repMin': repMin,
      'repMax': repMax,
      'increment': increment,
      'requiredConsecutiveSessions': requiredConsecutiveSessions,
      'reassessAfterDays': reassessAfterDays,
      'secondsMin': secondsMin,
      'secondsMax': secondsMax,
      'secondsIncrement': secondsIncrement,
    };
    putOpt(j, 'targetRIR', targetRIR);
    putOpt(j, 'initialWeight', initialWeight);
    putOpt(j, 'availableWeights', availableWeights);
    return j;
  }
}

// MARK: - Comparability

class ComparabilityContext {
  final String exerciseId;
  final String? variantLabel;
  final String? equipmentLabel;
  final LoadMode loadMode;

  const ComparabilityContext({
    required this.exerciseId,
    this.variantLabel,
    this.equipmentLabel,
    required this.loadMode,
  });

  /// Labels trimmed, case- and diacritic-insensitive, whitespace collapsed, empty → null.
  ComparabilityContext get normalized => ComparabilityContext(
    exerciseId: exerciseId.toUpperCase(),
    variantLabel: normalizeLabel(variantLabel),
    equipmentLabel: normalizeLabel(equipmentLabel),
    loadMode: loadMode,
  );

  /// Swift: trim `.whitespacesAndNewlines`, fold case and diacritics (es_AR), collapse whitespace.
  static String? normalizeLabel(String? label) {
    if (label == null) return null;
    final folded = foldDiacritics(swiftTrim(label));
    final collapsed = splitOnWhitespace(folded).join(' ');
    return collapsed.isEmpty ? null : collapsed;
  }

  /// Unambiguous identity of the normalized context (Swift compares the normalized structs; the
  /// sort key can collide, e.g. variant "a|b" vs. variant "a" + equipment "b|").
  String get identityKey {
    final n = normalized;
    return jsonEncode([n.exerciseId, n.variantLabel, n.equipmentLabel, n.loadMode.name]);
  }

  /// Stable string used for deterministic ordering only (same as Swift `sortKey`).
  String get sortKey {
    final n = normalized;
    return '${n.exerciseId}|${n.variantLabel ?? ''}|${n.equipmentLabel ?? ''}|${n.loadMode.name}';
  }

  ComparabilityContext copyWith({
    String? variantLabel,
    String? equipmentLabel,
    bool clearVariant = false,
    bool clearEquipment = false,
  }) => ComparabilityContext(
    exerciseId: exerciseId,
    variantLabel: clearVariant ? null : (variantLabel ?? this.variantLabel),
    equipmentLabel: clearEquipment ? null : (equipmentLabel ?? this.equipmentLabel),
    loadMode: loadMode,
  );

  @override
  bool operator ==(Object other) =>
      other is ComparabilityContext &&
      other.exerciseId == exerciseId &&
      other.variantLabel == variantLabel &&
      other.equipmentLabel == equipmentLabel &&
      other.loadMode == loadMode;

  @override
  int get hashCode => Object.hash(exerciseId, variantLabel, equipmentLabel, loadMode);

  factory ComparabilityContext.fromJson(Json j) => ComparabilityContext(
    exerciseId: uuidFromJson(j['exerciseId']),
    variantLabel: j['variantLabel'] as String?,
    equipmentLabel: j['equipmentLabel'] as String?,
    loadMode: enumFromName(LoadMode.values, j['loadMode']),
  );

  Json toJson() {
    final j = <String, Object?>{'exerciseId': exerciseId, 'loadMode': loadMode.name};
    putOpt(j, 'variantLabel', variantLabel);
    putOpt(j, 'equipmentLabel', equipmentLabel);
    return j;
  }
}

class ComparabilityLink {
  final String id;
  final ComparabilityContext a;
  final ComparabilityContext b;
  final DateTime createdAt;

  const ComparabilityLink({required this.id, required this.a, required this.b, required this.createdAt});

  factory ComparabilityLink.fromJson(Json j) => ComparabilityLink(
    id: uuidFromJson(j['id']),
    a: ComparabilityContext.fromJson(asJson(j['a'])),
    b: ComparabilityContext.fromJson(asJson(j['b'])),
    createdAt: dateFromJson(j['createdAt']),
  );

  Json toJson() => {'id': id, 'a': a.toJson(), 'b': b.toJson(), 'createdAt': dateToJson(createdAt)};
}

/// Transitive closure of links (BFS), identical traversal to Swift.
class ComparabilityResolver {
  final List<ComparabilityLink> links;
  const ComparabilityResolver(this.links);

  /// Equivalence class as a set of normalized identity keys (`ComparabilityContext.identityKey`).
  Set<String> equivalenceClass(ComparabilityContext context) {
    final start = context.normalized;
    final visited = <String>{start.identityKey};
    final frontier = <ComparabilityContext>[start];
    final edges = links.map((l) => (l.a.normalized, l.b.normalized)).toList();
    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();
      for (final (a, b) in edges) {
        if (a == current && !visited.contains(b.identityKey)) {
          visited.add(b.identityKey);
          frontier.add(b);
        } else if (b == current && !visited.contains(a.identityKey)) {
          visited.add(a.identityKey);
          frontier.add(a);
        }
      }
    }
    return visited;
  }

  bool areComparable(ComparabilityContext lhs, ComparabilityContext rhs) =>
      lhs.normalized == rhs.normalized || equivalenceClass(lhs).contains(rhs.identityKey);
}

// MARK: - Exercise

class MuscleInvolvement {
  final MuscleGroup muscle;
  final double? factor;
  const MuscleInvolvement(this.muscle, [this.factor]);

  factory MuscleInvolvement.fromJson(Json j) =>
      MuscleInvolvement(enumFromName(MuscleGroup.values, j['muscle']), optDouble(j['factor']));

  Json toJson() {
    final j = <String, Object?>{'muscle': muscle.name};
    putOpt(j, 'factor', factor);
    return j;
  }

  @override
  bool operator ==(Object other) => other is MuscleInvolvement && other.muscle == muscle && other.factor == factor;

  @override
  int get hashCode => Object.hash(muscle, factor);
}

class Exercise {
  String id;
  String? catalogId;
  String name;
  MeasurementType measurement;
  Equipment equipment;
  LoadMode loadMode;
  List<MuscleGroup> primaryMuscles;
  List<MuscleInvolvement> secondaryMuscles;
  double defaultIncrement;
  List<double>? availableWeights;
  ProgressionConfig progression;
  int? defaultRestSeconds;
  String notes;
  bool isCustom;
  bool isArchived;

  Exercise({
    required this.id,
    this.catalogId,
    required this.name,
    this.measurement = MeasurementType.weightReps,
    this.equipment = Equipment.barbell,
    this.loadMode = LoadMode.total,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.defaultIncrement = 2.5,
    this.availableWeights,
    ProgressionConfig? progression,
    this.defaultRestSeconds,
    this.notes = '',
    this.isCustom = false,
    this.isArchived = false,
  }) : progression = progression ?? ProgressionConfig();

  ComparabilityContext get defaultContext => ComparabilityContext(exerciseId: id, loadMode: loadMode);

  Exercise copy() => Exercise.fromJson(toJson());

  factory Exercise.fromJson(Json j) => Exercise(
    id: uuidFromJson(j['id']),
    catalogId: j['catalogId'] as String?,
    name: j['name'] as String,
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    equipment: enumFromName(Equipment.values, j['equipment']),
    loadMode: enumFromName(LoadMode.values, j['loadMode']),
    primaryMuscles: listOf(j['primaryMuscles'], (e) => enumFromName(MuscleGroup.values, e)),
    secondaryMuscles: listOf(j['secondaryMuscles'], (e) => MuscleInvolvement.fromJson(asJson(e))),
    defaultIncrement: toDouble(j['defaultIncrement']),
    availableWeights: j['availableWeights'] == null ? null : listOf(j['availableWeights'], toDouble),
    progression: ProgressionConfig.fromJson(asJson(j['progression'])),
    defaultRestSeconds: optInt(j['defaultRestSeconds']),
    notes: j['notes'] as String,
    isCustom: j['isCustom'] as bool,
    isArchived: j['isArchived'] as bool,
  );

  Json toJson() {
    final j = <String, Object?>{
      'id': id,
      'name': name,
      'measurement': measurement.name,
      'equipment': equipment.name,
      'loadMode': loadMode.name,
      'primaryMuscles': primaryMuscles.map((m) => m.name).toList(),
      'secondaryMuscles': secondaryMuscles.map((m) => m.toJson()).toList(),
      'defaultIncrement': defaultIncrement,
      'progression': progression.toJson(),
      'notes': notes,
      'isCustom': isCustom,
      'isArchived': isArchived,
    };
    putOpt(j, 'catalogId', catalogId);
    putOpt(j, 'availableWeights', availableWeights);
    putOpt(j, 'defaultRestSeconds', defaultRestSeconds);
    return j;
  }
}

/// Fields of an exercise frozen inside each log.
class ExerciseSnapshot {
  String exerciseId;
  String name;
  MeasurementType measurement;
  Equipment equipment;
  LoadMode loadMode;
  List<MuscleGroup> primaryMuscles;
  List<MuscleInvolvement> secondaryMuscles;

  ExerciseSnapshot({
    required this.exerciseId,
    required this.name,
    required this.measurement,
    required this.equipment,
    required this.loadMode,
    required this.primaryMuscles,
    required this.secondaryMuscles,
  });

  factory ExerciseSnapshot.of(Exercise e) => ExerciseSnapshot(
    exerciseId: e.id,
    name: e.name,
    measurement: e.measurement,
    equipment: e.equipment,
    loadMode: e.loadMode,
    primaryMuscles: List.of(e.primaryMuscles),
    secondaryMuscles: List.of(e.secondaryMuscles),
  );

  factory ExerciseSnapshot.fromJson(Json j) => ExerciseSnapshot(
    exerciseId: uuidFromJson(j['exerciseId']),
    name: j['name'] as String,
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    equipment: enumFromName(Equipment.values, j['equipment']),
    loadMode: enumFromName(LoadMode.values, j['loadMode']),
    primaryMuscles: listOf(j['primaryMuscles'], (e) => enumFromName(MuscleGroup.values, e)),
    secondaryMuscles: listOf(j['secondaryMuscles'], (e) => MuscleInvolvement.fromJson(asJson(e))),
  );

  Json toJson() => {
    'exerciseId': exerciseId,
    'name': name,
    'measurement': measurement.name,
    'equipment': equipment.name,
    'loadMode': loadMode.name,
    'primaryMuscles': primaryMuscles.map((m) => m.name).toList(),
    'secondaryMuscles': secondaryMuscles.map((m) => m.toJson()).toList(),
  };
}

// MARK: - Performance

class PerformedSet {
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

  PerformedSet({
    required this.index,
    this.kind = SetKind.working,
    this.status = SetStatus.completed,
    this.weight,
    this.reps,
    this.seconds,
    this.addedWeight,
    this.assistance,
    this.rir,
    this.rpe,
    this.completedAt,
    this.excludedFromEstimates = false,
  });

  PerformedSet copyWithIndex(int i) => PerformedSet(
    index: i,
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

  /// Recorded RIR, or 10 − RPE when only RPE exists.
  double? get effectiveRIR {
    if (rir != null) return rir;
    if (rpe != null) return (10 - rpe!) < 0 ? 0 : 10 - rpe!;
    return null;
  }

  double get netAddedLoad => (addedWeight ?? 0) - (assistance ?? 0);

  double progressionLoad(MeasurementType m) => switch (m) {
    MeasurementType.weightReps => weight ?? 0,
    MeasurementType.bodyweightReps => netAddedLoad,
    MeasurementType.duration => weight ?? 0,
  };

  bool isValidCompleted(MeasurementType m) {
    if (status != SetStatus.completed) return false;
    switch (m) {
      case MeasurementType.weightReps:
        final w = weight, r = reps;
        return w != null && w.isFinite && w >= 0 && r != null && r >= 1;
      case MeasurementType.bodyweightReps:
        final r = reps;
        if (r == null || r < 1) return false;
        final a = addedWeight, s = assistance;
        if (a != null && !(a.isFinite && a >= 0)) return false;
        if (s != null && !(s.isFinite && s >= 0)) return false;
        return true;
      case MeasurementType.duration:
        final s = seconds;
        if (s == null || s < 1) return false;
        final w = weight;
        if (w != null && !(w.isFinite && w >= 0)) return false;
        return true;
    }
  }

  bool isEffective(MeasurementType m) => kind.countsAsEffectiveWork && isValidCompleted(m);

  bool feedsProgression(MeasurementType m) => kind.feedsProgression && isValidCompleted(m);

  int amount(MeasurementType m) => switch (m) {
    MeasurementType.weightReps || MeasurementType.bodyweightReps => reps ?? 0,
    MeasurementType.duration => seconds ?? 0,
  };

  factory PerformedSet.fromJson(Json j) => PerformedSet(
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
  );

  Json toJson() {
    final j = <String, Object?>{
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
    return j;
  }
}

class ExercisePerformance {
  String sessionId;
  String exerciseLogId;
  DateTime sessionStart;
  SessionStatus sessionStatus;
  bool isAtypical;
  ComparabilityContext context;
  MeasurementType measurement;
  List<PerformedSet> sets;

  ExercisePerformance({
    required this.sessionId,
    required this.exerciseLogId,
    required this.sessionStart,
    this.sessionStatus = SessionStatus.completed,
    this.isAtypical = false,
    required this.context,
    this.measurement = MeasurementType.weightReps,
    required this.sets,
  });

  ExercisePerformance copyWith({ComparabilityContext? context, List<PerformedSet>? sets}) => ExercisePerformance(
    sessionId: sessionId,
    exerciseLogId: exerciseLogId,
    sessionStart: sessionStart,
    sessionStatus: sessionStatus,
    isAtypical: isAtypical,
    context: context ?? this.context,
    measurement: measurement,
    sets: sets ?? this.sets,
  );

  List<PerformedSet> get effectiveSets =>
      stableSorted(sets.where((s) => s.isEffective(measurement)), (a, b) => a.index.compareTo(b.index));

  List<PerformedSet> get progressionSets =>
      stableSorted(sets.where((s) => s.feedsProgression(measurement)), (a, b) => a.index.compareTo(b.index));

  factory ExercisePerformance.fromJson(Json j) => ExercisePerformance(
    sessionId: uuidFromJson(j['sessionId']),
    exerciseLogId: uuidFromJson(j['exerciseLogId']),
    sessionStart: dateFromJson(j['sessionStart']),
    sessionStatus: enumFromName(SessionStatus.values, j['sessionStatus']),
    isAtypical: j['isAtypical'] as bool,
    context: ComparabilityContext.fromJson(asJson(j['context'])),
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    sets: listOf(j['sets'], (e) => PerformedSet.fromJson(asJson(e))),
  );

  Json toJson() => {
    'sessionId': sessionId,
    'exerciseLogId': exerciseLogId,
    'sessionStart': dateToJson(sessionStart),
    'sessionStatus': sessionStatus.name,
    'isAtypical': isAtypical,
    'context': context.toJson(),
    'measurement': measurement.name,
    'sets': sets.map((s) => s.toJson()).toList(),
  };
}
