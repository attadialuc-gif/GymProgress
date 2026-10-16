/// Ports of RecommendationText.swift, DoubleProgressionStrategy.swift and ProgressionEngine.
/// Rule order and rationale: docs/FORMULAS.md §8.2 and docs/DECISIONS.md (D-010…D-016).
library;

import 'analysis.dart';
import 'calendar.dart';
import 'enums.dart';
import 'formatting.dart';
import 'load_math.dart';
import 'models.dart';
import 'recommendation.dart';

/// Spanish (es-AR) explanation texts. Same wording as the Swift app.
class RecommendationText {
  final GymLocale locale;
  final MeasurementType measurement;
  final LoadMode loadMode;
  final ProgressionConfig config;

  const RecommendationText(this.locale, this.measurement, this.loadMode, this.config);

  String get _unit => measurement == MeasurementType.duration ? 'segundos' : 'repeticiones';
  int get _top => measurement == MeasurementType.duration ? config.secondsMax : config.repMax;
  int get _bottom => measurement == MeasurementType.duration ? config.secondsMin : config.repMin;

  String load(double value) => GymFormat.load(value, measurement, loadMode, locale: locale);

  String get _rangeText => measurement == MeasurementType.duration
      ? '${config.secondsMin}–${config.secondsMax} s'
      : '${config.repMin}–${config.repMax}';

  String get _effortPhrase {
    final rir = config.targetRIR;
    if (rir != null) return 'te quedaron unas $rir repeticiones en reserva';
    return 'el esfuerzo fue exigente pero controlado';
  }

  String get noHistory =>
      'Todavía no hay datos suficientes para recomendar una carga. Configurá un objetivo inicial (peso y rango) para empezar.';

  String get noHistoryInContext =>
      'Todavía no hay datos suficientes en este contexto (otra máquina, variante o modo de carga). El historial anterior se muestra solo como referencia no equivalente.';

  String initialTarget(double weight, {required bool hasNonEquivalentReference}) {
    final tail = hasNonEquivalentReference
        ? 'No hay sesiones comparables en este contexto; el historial de otro contexto es solo referencia.'
        : 'Todavía no hay sesiones anteriores para comparar.';
    return 'Objetivo inicial configurado por vos: ${load(weight)} × $_rangeText. $tail';
  }

  String longBreak(int days, double weight) =>
      'Pasaron $days días desde la última sesión comparable. Reevaluá la carga antes de subir: retomá con ${load(weight)} o menos.';

  String incompleteSets(int done, double weight, {required bool mixedLoads}) {
    final withLoad = mixedLoads ? 'con la misma carga (${load(weight)})' : 'con ${load(weight)}';
    return 'En la última sesión completaste $done de ${config.targetSets} series $withLoad. Mantené la carga y completá todas las series antes de subir.';
  }

  String increaseHigh(double next) {
    final effort = config.targetRIR == null ? '' : ' con el esfuerzo objetivo';
    return 'Alcanzaste $_top $_unit en todas las series$effort. Subí a ${load(next)} y volvé a $_bottom $_unit.';
  }

  String increaseConditional(double next) {
    if (config.targetRIR == null) {
      return 'Podrías subir a ${load(next)} si las series se hicieron con buena técnica y un esfuerzo exigente pero controlado.';
    }
    return 'Podrías subir a ${load(next)} si las series se hicieron con buena técnica y cerca del esfuerzo objetivo.';
  }

  List<String> get increaseConditions => [
    'No se registró el RIR/RPE de todas las series, así que no se puede confirmar el esfuerzo.',
    'Subí solo si la técnica fue buena y $_effortPhrase.',
  ];

  String noHeavierLoad(double weight) =>
      'Alcanzaste el tope del rango, pero no hay un peso disponible mayor a ${load(weight)}. Mantené la carga o actualizá los pesos disponibles.';

  String get noHeavierLoadNote =>
      'Agregá pesos disponibles o cambiá el incremento en los criterios de progresión del ejercicio.';

  String get bodyweightLoadNote =>
      'Para sumar carga necesitás cinturón o chaleco con lastre; si no, podés seguir sumando repeticiones.';

  String needsConfirmation(int achieved, int required, double weight) =>
      'Alcanzaste el tope del rango ($achieved de $required sesiones consecutivas requeridas). Repetí ${load(weight)} para confirmarlo.';

  String effortAboveTarget(double weight) {
    final rir = config.targetRIR == null ? '' : ' (RIR ${config.targetRIR})';
    return 'Llegaste a $_top $_unit, pero con menos reserva que la objetivo$rir: el esfuerzo estuvo por encima del previsto. Mantené ${load(weight)} hasta lograrlo con el esfuerzo objetivo.';
  }

  String repeatedBelowMin() =>
      'Dos sesiones comparables seguidas con series por debajo de $_bottom $_unit. Reevaluá descanso, sueño, técnica y carga; bajar el peso es una opción que decidís vos.';

  String performanceDroppedSameLoad(int lastTotal, int previousTotal, double weight) =>
      'Rendimiento menor que la sesión anterior ($lastTotal vs. $previousTotal $_unit con ${load(weight)}). Mantené la carga y revisá descanso, sueño y técnica: una sola sesión no justifica cambiarla.';

  String belowMin(double weight) =>
      'Algunas series quedaron por debajo de $_bottom $_unit. Mantené ${load(weight)} y apuntá a llegar a $_bottom en todas.';

  String belowTop(double weight) {
    if (measurement == MeasurementType.duration) {
      return 'Rango superior no alcanzado. Mantené ${load(weight)} y sumá ${config.secondsIncrement} segundos en las series por debajo de $_top s.';
    }
    return 'Rango superior no alcanzado. Mantené ${load(weight)} y sumá 1 repetición en las series por debajo de $_top.';
  }

  List<String> get belowTopConditions => [
    'No se registró el RIR/RPE de todas las series: sumá solo si podés mantener la técnica y $_effortPhrase.',
  ];

  String repsHeldByEffort(double weight) {
    final rir = config.targetRIR == null ? '' : ' (RIR ${config.targetRIR})';
    return 'Rango superior no alcanzado y el esfuerzo ya estuvo por encima del objetivo$rir. Mantené ${load(weight)} y las mismas $_unit hasta que te resulte más cómodo.';
  }

  String durationTopReached(double weight) =>
      'Alcanzaste $_top segundos en todas las series con ${load(weight)}. Mantené y, si querés progresar, probá una variante más difícil o sumá carga.';

  String get plateauNote =>
      'Posible estancamiento: las últimas sesiones comparables no muestran una mejora clara. Revisá descanso, técnica o la estrategia.';

  String get decliningNote =>
      'Tendencia en descenso en las últimas sesiones comparables. Revisá el contexto antes de cambiar la carga.';
}

enum Effort {
  /// Some recorded RIR is below the target.
  belowTarget,

  /// All sets recorded and at or above the target.
  meetsTarget,

  /// All sets recorded, no target configured.
  recordedNoTarget,

  /// Missing for at least one set (and none below target).
  unknown;

  bool get isConfirmed => this == Effort.meetsTarget || this == Effort.recordedNoTarget;
}

class PerformanceDrop {
  final int lastTotal;
  final int previousTotal;
  const PerformanceDrop(this.lastTotal, this.previousTotal);
}

/// Pure and deterministic: same input → same output.
abstract class ProgressionStrategy {
  ProgressionStrategyKind get kind;
  Recommendation recommend(ProgressionInput input);
}

class ProgressionEngine {
  static ProgressionStrategy strategy(ProgressionStrategyKind kind) => switch (kind) {
    ProgressionStrategyKind.doubleProgression => const DoubleProgressionStrategy(),
  };

  static Recommendation recommend(ProgressionInput input) => strategy(input.config.strategy).recommend(input);
}

/// Default strategy: double progression (reps first inside the range, then load).
class DoubleProgressionStrategy implements ProgressionStrategy {
  const DoubleProgressionStrategy();

  @override
  ProgressionStrategyKind get kind => ProgressionStrategyKind.doubleProgression;

  @override
  Recommendation recommend(ProgressionInput input) {
    final config = input.config.sanitized();
    final m = input.measurement;
    final text = RecommendationText(GymLocale.of(input.locale), m, input.context.loadMode, config);
    final calendar = TrainingCalendar(timeZone: input.timeZone, firstWeekday: input.firstWeekday);
    final comparable = HistoryAnalyzer.comparable(input);
    final summaries = comparable.map(HistoryAnalyzer.summary).toList();

    final isDuration = m == MeasurementType.duration;
    final top = isDuration ? config.secondsMax : config.repMax;
    final bottom = isDuration ? config.secondsMin : config.repMin;
    final step = isDuration ? config.secondsIncrement : 1;
    final sets = config.targetSets;

    final rec = Recommendation(
      strategy: kind,
      action: RecommendationAction.maintain,
      reason: RecommendationReason.noComparableHistory,
      confidence: RecommendationConfidence.high,
      measurement: m,
      targetReps: [],
      target: SessionTarget.fromConfig(config),
      reasonText: '',
      conditions: [],
      notes: [],
      context: input.context,
      lastPerformance: summaries.isEmpty ? null : summaries.first,
      evidence: summaries.take(5).toList(),
      trend: TrendAnalyzer.classifyPerformances(
        comparable.reversed.toList(),
        oneRepMax: input.oneRepMax,
        thresholds: input.trendThresholds,
      ),
      generatedAt: input.now,
    );

    void setAmounts(List<int> amounts) {
      if (isDuration) {
        rec.targetSeconds = amounts;
        rec.targetReps = [];
      } else {
        rec.targetReps = amounts;
        rec.targetSeconds = null;
      }
    }

    List<int> repeat(int value, int count) => List.filled(count < 0 ? 0 : count, value);
    int clamp(int v) => v < bottom ? bottom : (v > top ? top : v);

    // Rule 1 — no comparable history.
    if (comparable.isEmpty) {
      final refPerf = HistoryAnalyzer.nonEquivalentReference(input);
      final reference = refPerf == null ? null : HistoryAnalyzer.summary(refPerf);
      rec.nonEquivalentReference = reference;
      rec.action = RecommendationAction.needsInitialTarget;
      final initial = config.initialWeight;
      if (initial != null) {
        rec.reason = RecommendationReason.initialTarget;
        rec.targetWeight = LoadMath.normalized(initial);
        setAmounts(repeat(bottom, sets));
        rec.reasonText = text.initialTarget(initial, hasNonEquivalentReference: reference != null);
      } else {
        rec.reason = reference == null
            ? RecommendationReason.noComparableHistory
            : RecommendationReason.noComparableHistoryInContext;
        rec.reasonText = reference == null ? text.noHistory : text.noHistoryInContext;
      }
      return rec;
    }
    final last = comparable.first;
    final lastSummary = summaries.first;

    final load = lastSummary.workingLoad;
    rec.targetWeight = load;
    switch (rec.trend) {
      case TrendClassification.possiblePlateau:
        rec.notes.add(text.plateauNote);
      case TrendClassification.declining:
        rec.notes.add(text.decliningNote);
      case TrendClassification.insufficientData:
      case TrendClassification.progressing:
      case TrendClassification.stable:
        break;
    }

    // Rule 2 — long break.
    final days = calendar.daysBetween(last.sessionStart, input.now);
    if (days > config.reassessAfterDays) {
      rec.action = RecommendationAction.reassess;
      rec.reason = RecommendationReason.longBreak;
      setAmounts(repeat(bottom, sets));
      rec.reasonText = text.longBreak(days, load);
      return rec;
    }

    final evaluated = HistoryAnalyzer.evaluatedSets(last, sets);
    final amounts = evaluated.map((s) => s.amount(m)).toList();

    // Rule 3 — incomplete sets.
    if (evaluated.length < sets) {
      rec.action = RecommendationAction.maintain;
      rec.reason = RecommendationReason.incompleteSets;
      final kept = amounts.map(clamp).toList();
      setAmounts([...kept, ...repeat(bottom, sets - kept.length)]);
      rec.reasonText = text.incompleteSets(evaluated.length, load, mixedLoads: last.progressionSets.length >= sets);
      return rec;
    }

    final effort = assessEffort(evaluated, config.targetRIR);
    final allTop = amounts.every((a) => a >= top);

    if (allTop) {
      if (isDuration) {
        rec.action = RecommendationAction.maintain;
        rec.reason = RecommendationReason.durationTopReached;
        setAmounts(repeat(top, sets));
        rec.reasonText = text.durationTopReached(load);
        return rec;
      }

      // Rule 5 — reps reached but effort above target: never increase.
      if (effort == Effort.belowTarget) {
        rec.action = RecommendationAction.maintain;
        rec.reason = RecommendationReason.effortAboveTarget;
        setAmounts(repeat(top, sets));
        rec.reasonText = text.effortAboveTarget(load);
        return rec;
      }

      // Rule 4 — consecutive sessions at the top of the range.
      final streak = topStreak(comparable, load, sets, top, m);
      if (streak < config.requiredConsecutiveSessions) {
        rec.action = RecommendationAction.maintain;
        rec.reason = RecommendationReason.topOfRangeNeedsConfirmation;
        setAmounts(repeat(top, sets));
        rec.reasonText = text.needsConfirmation(streak, config.requiredConsecutiveSessions, load);
        return rec;
      }

      final next = nextLoad(load, m, config);
      if (next == null) {
        rec.action = RecommendationAction.maintain;
        rec.reason = RecommendationReason.topOfRangeNoHeavierLoad;
        setAmounts(repeat(top, sets));
        rec.reasonText = text.noHeavierLoad(load);
        rec.notes.add(text.noHeavierLoadNote);
        return rec;
      }

      rec.action = RecommendationAction.increaseWeight;
      rec.reason = RecommendationReason.topOfRangeReached;
      rec.targetWeight = next;
      setAmounts(repeat(bottom, sets));
      if (m == MeasurementType.bodyweightReps && LoadMath.key(load) >= 0) {
        rec.notes.add(text.bodyweightLoadNote);
      }
      if (effort.isConfirmed) {
        rec.confidence = RecommendationConfidence.high;
        rec.reasonText = text.increaseHigh(next);
      } else {
        rec.confidence = RecommendationConfidence.conditional;
        rec.reasonText = text.increaseConditional(next);
        rec.conditions = text.increaseConditions;
      }
      return rec;
    }

    // Below the top of the range. The previous comparable session only counts as "consecutive"
    // when it is not separated from the last one by a long break.
    ExercisePerformance? previous;
    if (comparable.length > 1) {
      final p = comparable[1];
      if (calendar.daysBetween(p.sessionStart, last.sessionStart) <= config.reassessAfterDays) previous = p;
    }
    final belowMin = amounts.any((a) => a < bottom);

    // Rule 7b — sets below the minimum in 2 consecutive comparable sessions (any load).
    if (belowMin &&
        previous != null &&
        HistoryAnalyzer.evaluatedSets(previous, sets).any((s) => s.amount(m) < bottom)) {
      rec.action = RecommendationAction.reassess;
      rec.reason = RecommendationReason.repeatedBelowRepMin;
      setAmounts(repeat(bottom, sets));
      rec.reasonText = text.repeatedBelowMin();
      return rec;
    }

    // Rule 7 — fewer reps than the previous comparable session at the same load.
    if (previous != null) {
      final drop = performanceDrop(last, previous, sets, m);
      if (drop != null) {
        rec.action = RecommendationAction.maintain;
        rec.reason = RecommendationReason.performanceDropped;
        final previousAmounts = HistoryAnalyzer.evaluatedSets(previous, sets).map((s) => clamp(s.amount(m))).toList();
        setAmounts([...previousAmounts, ...repeat(bottom, sets - previousAmounts.length)]);
        rec.reasonText = text.performanceDroppedSameLoad(drop.lastTotal, drop.previousTotal, load);
        return rec;
      }
    }

    if (belowMin) {
      rec.action = RecommendationAction.maintain;
      rec.reason = RecommendationReason.belowRepMin;
      setAmounts(amounts.map(clamp).toList());
      rec.reasonText = text.belowMin(load);
      return rec;
    }

    // Rule 6 — inside the range: same load, +1 rep (or +step seconds) on sets below the top.
    if (effort == Effort.belowTarget) {
      rec.action = RecommendationAction.maintain;
      rec.reason = RecommendationReason.repsHeldByEffort;
      setAmounts(amounts);
      rec.reasonText = text.repsHeldByEffort(load);
      return rec;
    }

    rec.action = RecommendationAction.increaseReps;
    rec.reason = RecommendationReason.belowTopOfRange;
    setAmounts(amounts.map((a) => a < top ? (a + step < top ? a + step : top) : a).toList());
    rec.reasonText = text.belowTop(load);
    if (effort.isConfirmed) {
      rec.confidence = RecommendationConfidence.high;
    } else {
      rec.confidence = RecommendationConfidence.conditional;
      rec.conditions = text.belowTopConditions;
    }
    return rec;
  }

  // MARK: - Helpers

  static Effort assessEffort(List<PerformedSet> sets, int? targetRIR) {
    final values = sets.map((s) => s.effectiveRIR).toList();
    if (targetRIR != null && values.any((v) => (v ?? double.infinity) < targetRIR.toDouble())) {
      return Effort.belowTarget;
    }
    if (!values.every((v) => v != null)) return Effort.unknown;
    return targetRIR == null ? Effort.recordedNoTarget : Effort.meetsTarget;
  }

  static int topStreak(List<ExercisePerformance> comparable, double load, int sets, int top, MeasurementType m) {
    var streak = 0;
    for (final performance in comparable) {
      final l = HistoryAnalyzer.workingLoad(performance);
      if (l == null || !LoadMath.isEqual(l, load)) break;
      final evaluated = HistoryAnalyzer.evaluatedSets(performance, sets);
      if (evaluated.length < sets || !evaluated.every((s) => s.amount(m) >= top)) break;
      streak++;
    }
    return streak;
  }

  /// Next real load. Body-weight work with assistance reduces the assistance first.
  static double? nextLoad(double load, MeasurementType m, ProgressionConfig config) {
    if (m == MeasurementType.bodyweightReps && LoadMath.key(load) < 0) {
      final v = load + config.increment;
      return LoadMath.normalized(v < 0 ? v : 0);
    }
    return LoadMath.nextLoad(load, config.increment, config.availableWeights);
  }

  /// Fewer total reps (or seconds) than the previous comparable session at the same load, over the
  /// sets both share (D-015).
  static PerformanceDrop? performanceDrop(
    ExercisePerformance last,
    ExercisePerformance previous,
    int sets,
    MeasurementType m,
  ) {
    final lastLoad = HistoryAnalyzer.workingLoad(last);
    final previousLoad = HistoryAnalyzer.workingLoad(previous);
    if (lastLoad == null || previousLoad == null || !LoadMath.isEqual(lastLoad, previousLoad)) return null;
    final lastSets = HistoryAnalyzer.evaluatedSets(last, sets);
    final previousSets = HistoryAnalyzer.evaluatedSets(previous, sets);
    final k = lastSets.length < previousSets.length ? lastSets.length : previousSets.length;
    if (k <= 0) return null;
    final lastTotal = lastSets.take(k).fold<int>(0, (a, s) => a + s.amount(m));
    final previousTotal = previousSets.take(k).fold<int>(0, (a, s) => a + s.amount(m));
    return lastTotal < previousTotal ? PerformanceDrop(lastTotal, previousTotal) : null;
  }
}
