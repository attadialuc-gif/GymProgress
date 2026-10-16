/// Port of Recommendation.swift (same JSON as Swift `Codable`).
library;

import 'enums.dart';
import 'json_util.dart';
import 'models.dart';

enum RecommendationAction { needsInitialTarget, increaseWeight, increaseReps, maintain, reassess }

enum RecommendationConfidence { high, conditional }

enum RecommendationReason {
  noComparableHistory,
  noComparableHistoryInContext,
  initialTarget,
  longBreak,
  incompleteSets,
  topOfRangeReached,
  topOfRangeNoHeavierLoad,
  topOfRangeNeedsConfirmation,
  effortAboveTarget,
  repeatedBelowRepMin,
  performanceDropped,
  belowRepMin,
  belowTopOfRange,
  repsHeldByEffort,
  durationTopReached,
}

enum TrendClassification { insufficientData, progressing, stable, possiblePlateau, declining }

class SessionTarget {
  final int sets, repMin, repMax, secondsMin, secondsMax;
  final int? targetRIR;

  SessionTarget.fromConfig(ProgressionConfig c)
    : sets = c.targetSets,
      repMin = c.repMin,
      repMax = c.repMax,
      targetRIR = c.targetRIR,
      secondsMin = c.secondsMin,
      secondsMax = c.secondsMax;

  SessionTarget.fromJson(Json j)
    : sets = toInt(j['sets']),
      repMin = toInt(j['repMin']),
      repMax = toInt(j['repMax']),
      targetRIR = optInt(j['targetRIR']),
      secondsMin = toInt(j['secondsMin']),
      secondsMax = toInt(j['secondsMax']);

  Json toJson() {
    final j = <String, Object?>{
      'sets': sets,
      'repMin': repMin,
      'repMax': repMax,
      'secondsMin': secondsMin,
      'secondsMax': secondsMax,
    };
    putOpt(j, 'targetRIR', targetRIR);
    return j;
  }
}

class SetSummary {
  final double load;
  final int amount;
  final double? rir;
  const SetSummary(this.load, this.amount, this.rir);

  factory SetSummary.fromJson(Json j) => SetSummary(toDouble(j['load']), toInt(j['amount']), optDouble(j['rir']));

  Json toJson() {
    final j = <String, Object?>{'load': load, 'amount': amount};
    putOpt(j, 'rir', rir);
    return j;
  }
}

class PerformanceSummary {
  final String sessionId;
  final String exerciseLogId;
  final DateTime date;
  final ComparabilityContext context;
  final MeasurementType measurement;
  final double workingLoad;
  final List<SetSummary> sets;

  const PerformanceSummary({
    required this.sessionId,
    required this.exerciseLogId,
    required this.date,
    required this.context,
    required this.measurement,
    required this.workingLoad,
    required this.sets,
  });

  List<int> get amounts => sets.map((s) => s.amount).toList();

  factory PerformanceSummary.fromJson(Json j) => PerformanceSummary(
    sessionId: uuidFromJson(j['sessionId']),
    exerciseLogId: uuidFromJson(j['exerciseLogId']),
    date: dateFromJson(j['date']),
    context: ComparabilityContext.fromJson(asJson(j['context'])),
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    workingLoad: toDouble(j['workingLoad']),
    sets: listOf(j['sets'], (e) => SetSummary.fromJson(asJson(e))),
  );

  Json toJson() => {
    'sessionId': sessionId,
    'exerciseLogId': exerciseLogId,
    'date': dateToJson(date),
    'context': context.toJson(),
    'measurement': measurement.name,
    'workingLoad': workingLoad,
    'sets': sets.map((s) => s.toJson()).toList(),
  };
}

class Recommendation {
  ProgressionStrategyKind strategy;
  RecommendationAction action;
  RecommendationReason reason;
  RecommendationConfidence confidence;
  MeasurementType measurement;
  double? targetWeight;
  List<int> targetReps;
  List<int>? targetSeconds;
  SessionTarget target;
  String reasonText;
  List<String> conditions;
  List<String> notes;
  ComparabilityContext context;
  PerformanceSummary? lastPerformance;
  List<PerformanceSummary> evidence;
  PerformanceSummary? nonEquivalentReference;
  TrendClassification trend;
  DateTime generatedAt;

  Recommendation({
    required this.strategy,
    required this.action,
    required this.reason,
    required this.confidence,
    required this.measurement,
    this.targetWeight,
    required this.targetReps,
    this.targetSeconds,
    required this.target,
    required this.reasonText,
    required this.conditions,
    required this.notes,
    required this.context,
    this.lastPerformance,
    required this.evidence,
    this.nonEquivalentReference,
    required this.trend,
    required this.generatedAt,
  });

  List<String> get evidenceSessionIds => evidence.map((e) => e.sessionId).toList();

  factory Recommendation.fromJson(Json j) => Recommendation(
    strategy: enumFromName(ProgressionStrategyKind.values, j['strategy']),
    action: enumFromName(RecommendationAction.values, j['action']),
    reason: enumFromName(RecommendationReason.values, j['reason']),
    confidence: enumFromName(RecommendationConfidence.values, j['confidence']),
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    targetWeight: optDouble(j['targetWeight']),
    targetReps: listOf(j['targetReps'], toInt),
    targetSeconds: j['targetSeconds'] == null ? null : listOf(j['targetSeconds'], toInt),
    target: SessionTarget.fromJson(asJson(j['target'])),
    reasonText: j['reasonText'] as String,
    conditions: listOf(j['conditions'], (e) => e as String),
    notes: listOf(j['notes'], (e) => e as String),
    context: ComparabilityContext.fromJson(asJson(j['context'])),
    lastPerformance: j['lastPerformance'] == null ? null : PerformanceSummary.fromJson(asJson(j['lastPerformance'])),
    evidence: listOf(j['evidence'], (e) => PerformanceSummary.fromJson(asJson(e))),
    nonEquivalentReference: j['nonEquivalentReference'] == null
        ? null
        : PerformanceSummary.fromJson(asJson(j['nonEquivalentReference'])),
    trend: enumFromName(TrendClassification.values, j['trend']),
    generatedAt: dateFromJson(j['generatedAt']),
  );

  Json toJson() {
    final j = <String, Object?>{
      'strategy': strategy.name,
      'action': action.name,
      'reason': reason.name,
      'confidence': confidence.name,
      'measurement': measurement.name,
      'targetReps': targetReps,
      'target': target.toJson(),
      'reasonText': reasonText,
      'conditions': conditions,
      'notes': notes,
      'context': context.toJson(),
      'evidence': evidence.map((e) => e.toJson()).toList(),
      'trend': trend.name,
      'generatedAt': dateToJson(generatedAt),
    };
    putOpt(j, 'targetWeight', targetWeight);
    putOpt(j, 'targetSeconds', targetSeconds);
    putOpt(j, 'lastPerformance', lastPerformance?.toJson());
    putOpt(j, 'nonEquivalentReference', nonEquivalentReference?.toJson());
    return j;
  }
}
