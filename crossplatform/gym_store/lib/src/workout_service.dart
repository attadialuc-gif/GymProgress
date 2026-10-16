/// Session flow (port of WorkoutService.swift). Every call persists immediately through the
/// repository (incremental save). "Now" is always injected.
library;

import 'package:gym_core/gym_core.dart';

import 'history_service.dart';
import 'records.dart';
import 'repository.dart';

/// The user's answer to a recommendation.
sealed class DecisionChoice {
  const DecisionChoice();
}

/// Pre-fill the recommended load; recommended reps stay visible as targets.
class AcceptChoice extends DecisionChoice {
  const AcceptChoice();
}

/// Use the user's own load / reps (or seconds) as today's target.
class ModifyChoice extends DecisionChoice {
  final double? weight;
  final List<int> reps;
  final List<int>? seconds;
  const ModifyChoice({this.weight, this.reps = const [], this.seconds});
}

/// Pre-fill nothing.
class IgnoreChoice extends DecisionChoice {
  const IgnoreChoice();
}

class RestAdvice {
  /// null = no rest (continue the superset round).
  final int? restSeconds;

  /// Next exercise of the superset to go to, if any.
  final String? nextExerciseLogId;
  const RestAdvice(this.restSeconds, this.nextExerciseLogId);
}

/// Everything the exercise screen needs, with the recommendation card on top.
class ExerciseLogState {
  final ExerciseLog log;
  final List<SetLog> sets;

  /// Frozen when the exercise was first opened; never recomputed afterwards (except on a context
  /// change before any decision).
  final Recommendation recommendation;
  final RecommendationDecision? decision;
  const ExerciseLogState(this.log, this.sets, this.recommendation, this.decision);
}

class WorkoutService {
  final GymRepository repository;

  /// IANA time zone of the user (device).
  final String timeZone;
  final GymLocale locale;

  WorkoutService(this.repository, {required this.timeZone, this.locale = GymLocale.esAR});

  HistoryService get _history => HistoryService(repository);

  TrainingCalendar get calendar =>
      TrainingCalendar(timeZone: timeZone, firstWeekday: repository.settings().firstWeekday);

  // MARK: - Session lifecycle

  /// The session to resume after a crash, call or lock (active or paused). At most one exists.
  WorkoutSession? openSession() {
    WorkoutSession? best;
    for (final s in repository.sessions()) {
      if (!s.isOpen) continue;
      if (best == null) {
        best = s;
        continue;
      }
      final c = best.startedAt.compareTo(s.startedAt);
      if (c < 0 || (c == 0 && best.id.compareTo(s.id) < 0)) best = s;
    }
    return best;
  }

  WorkoutSession startSession(String? routineId, {required DateTime now}) {
    return repository.transaction(() {
      if (openSession() != null) throw const GymStoreError(GymStoreErrorKind.sessionAlreadyOpen);
      String? routineName;
      var items = <RoutineExercise>[];
      if (routineId != null) {
        final routine = repository.routine(routineId);
        if (routine == null) throw const GymStoreError.notFound('routine');
        routineName = routine.name;
        items = repository.routineExercises(routineId);
      }
      final session = WorkoutSession(
        routineId: routineId,
        routineNameSnapshot: routineName,
        startedAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
      repository.upsertSession(session);

      var order = 0;
      for (final item in items) {
        final exercise = repository.exercise(item.exerciseId);
        if (exercise == null || exercise.isArchived) continue;
        final config = item.progressionOverride ?? exercise.progression;
        _createLog(
          session,
          exercise,
          config,
          routineExerciseId: item.id,
          restSeconds: item.restSeconds ?? exercise.defaultRestSeconds,
          notes: item.notes,
          order: order,
          supersetGroup: item.supersetGroup,
        );
        order++;
      }
      return session;
    });
  }

  void pause(String sessionId, {required DateTime now}) {
    repository.transaction(() {
      final session = _openSession(sessionId);
      if (session.status != SessionStatus.active) return;
      session
        ..status = SessionStatus.paused
        ..pauses.add(PauseInterval(now.toUtc()))
        ..updatedAt = now.toUtc();
      repository.upsertSession(session);
    });
  }

  void resume(String sessionId, {required DateTime now}) {
    repository.transaction(() {
      final session = _openSession(sessionId);
      if (session.status != SessionStatus.paused) return;
      _closePause(session, now);
      session
        ..status = SessionStatus.active
        ..updatedAt = now.toUtc();
      repository.upsertSession(session);
    });
  }

  WorkoutSession finish(String sessionId, {required DateTime now}) {
    return repository.transaction(() {
      final session = _openSession(sessionId);
      _closePause(session, now);
      session
        ..status = SessionStatus.completed
        ..endedAt = now.toUtc()
        ..updatedAt = now.toUtc();
      repository.upsertSession(session);
      return session;
    });
  }

  /// Marks the session as discarded (kept for audit, excluded everywhere). The UI must confirm first.
  void discard(String sessionId, {required DateTime now}) {
    repository.transaction(() {
      final session = _openSession(sessionId);
      _closePause(session, now);
      session
        ..status = SessionStatus.discarded
        ..endedAt = now.toUtc()
        ..updatedAt = now.toUtc();
      repository.upsertSession(session);
    });
  }

  void setSessionNotes(String sessionId, String notes, {required DateTime now}) {
    final session = repository.session(sessionId);
    if (session == null) throw const GymStoreError.notFound('session');
    repository.upsertSession(
      session
        ..notes = notes
        ..updatedAt = now.toUtc(),
    );
  }

  void setSessionAtypical(String sessionId, bool atypical, {required DateTime now}) {
    final session = repository.session(sessionId);
    if (session == null) throw const GymStoreError.notFound('session');
    repository.upsertSession(
      session
        ..isAtypical = atypical
        ..updatedAt = now.toUtc(),
    );
  }

  // MARK: - Exercises inside a session (session-only changes; the template is never touched)

  ExerciseLog addExercise(String sessionId, String exerciseId, {required DateTime now}) {
    return repository.transaction(() {
      final session = _openSession(sessionId);
      final exercise = repository.exercise(exerciseId);
      if (exercise == null) throw const GymStoreError.notFound('exercise');
      final orders = repository.exerciseLogsOfSession(sessionId).map((l) => l.plannedOrder);
      final order = (orders.isEmpty ? -1 : orders.reduce((a, b) => a > b ? a : b)) + 1;
      return _createLog(
        session,
        exercise,
        exercise.progression,
        restSeconds: exercise.defaultRestSeconds,
        notes: '',
        order: order,
      );
    });
  }

  /// Removes an exercise from this session only. Refused once a set was completed.
  void removeExercise(String logId) {
    repository.transaction(() {
      _requireOpenLog(logId);
      if (repository.setLogs(logId).any((s) => s.status == SetStatus.completed)) {
        throw const GymStoreError(GymStoreErrorKind.hasCompletedSets);
      }
      repository.deleteExerciseLog(logId);
    });
  }

  void moveExercises(String sessionId, List<String> orderedLogIds) {
    repository.transaction(() {
      for (var i = 0; i < orderedLogIds.length; i++) {
        final log = repository.exerciseLog(orderedLogIds[i]);
        if (log == null || log.sessionId != sessionId) continue;
        if (log.plannedOrder != i) repository.upsertExerciseLog(log..plannedOrder = i);
      }
    });
  }

  void setExerciseNotes(String logId, String notes) => repository.upsertExerciseLog(_requireLog(logId)..notes = notes);

  void setExerciseAtypical(String logId, bool atypical) =>
      repository.upsertExerciseLog(_requireLog(logId)..isAtypical = atypical);

  /// Changes the comparability context (machine / variant). Before any decision the recommendation
  /// is recomputed for the new context; after a decision, the decision and the frozen
  /// recommendation are kept untouched (the user's choice is the source of truth).
  ExerciseLog setContext(String logId, {String? variantLabel, String? equipmentLabel, required DateTime now}) {
    return repository.transaction(() {
      final log = _requireOpenLog(logId)
        ..variantLabel = cleanLabel(variantLabel)
        ..equipmentLabel = cleanLabel(equipmentLabel);
      if (log.frozenRecommendation != null && repository.decision(logId) == null) {
        log
          ..frozenRecommendation = computeRecommendation(log, now)
          ..recommendationFrozenAt = now.toUtc();
      }
      repository.upsertExerciseLog(log);
      return log;
    });
  }

  /// Manual "treat as equivalent" between two contexts. Only created by explicit user action.
  ComparabilityLink linkContexts(ComparabilityContext a, ComparabilityContext b, {required DateTime now}) {
    final link = ComparabilityLink(id: newUuid(), a: a, b: b, createdAt: now.toUtc());
    repository.insertComparabilityLink(link);
    return link;
  }

  /// The user switches machine/variant and says it is equivalent to the previous one: the link is
  /// created first, then the context changes.
  ExerciseLog switchContextTreatingAsEquivalent(
    String logId, {
    String? variantLabel,
    String? equipmentLabel,
    required DateTime now,
  }) {
    return repository.transaction(() {
      final log = _requireOpenLog(logId);
      final previous = log.context;
      final next = ComparabilityContext(
        exerciseId: previous.exerciseId,
        variantLabel: cleanLabel(variantLabel),
        equipmentLabel: cleanLabel(equipmentLabel),
        loadMode: previous.loadMode,
      );
      if (next.normalized != previous.normalized) linkContexts(previous, next, now: now);
      return setContext(logId, variantLabel: variantLabel, equipmentLabel: equipmentLabel, now: now);
    });
  }

  // MARK: - Recommendation

  /// Opens an exercise: computes the recommendation with history *prior* to this session and
  /// freezes it in the log the first time. Re-opening returns the frozen one and the decision.
  ExerciseLogState openExercise(String logId, {required DateTime now}) {
    return repository.transaction(() {
      final log = _requireLog(logId);
      if (log.frozenRecommendation == null) {
        log
          ..frozenRecommendation = computeRecommendation(log, now)
          ..recommendationFrozenAt = now.toUtc();
        repository.upsertExerciseLog(log);
      }
      return _state(log);
    });
  }

  /// Persists the user's decision and applies it to the pending sets. Changing one's mind updates
  /// the same decision (the originally shown recommendation stays as the audit snapshot).
  RecommendationDecision decide(String logId, DecisionChoice choice, {required DateTime now}) {
    return repository.transaction(() {
      final log = _requireOpenLog(logId);
      if (log.frozenRecommendation == null) {
        log
          ..frozenRecommendation = computeRecommendation(log, now)
          ..recommendationFrozenAt = now.toUtc();
        repository.upsertExerciseLog(log);
      }
      final recommendation = log.frozenRecommendation!;

      final DecisionKind kind;
      double? weight;
      List<int> reps;
      List<int>? seconds;
      switch (choice) {
        case AcceptChoice():
          kind = DecisionKind.accepted;
          weight = recommendation.targetWeight;
          reps = List.of(recommendation.targetReps);
          seconds = recommendation.targetSeconds == null ? null : List.of(recommendation.targetSeconds!);
        case ModifyChoice(weight: final w, reps: final r, seconds: final s):
          kind = DecisionKind.modified;
          if (w != null && !(w.isFinite && (w >= 0 || log.snapshot.measurement == MeasurementType.bodyweightReps))) {
            throw const GymStoreError.invalidValue('El peso no puede ser negativo.');
          }
          if (!r.every((x) => x >= 0) || !(s ?? const <int>[]).every((x) => x >= 0)) {
            throw const GymStoreError.invalidValue('Las repeticiones no pueden ser negativas.');
          }
          weight = w == null ? null : LoadMath.normalized(w);
          reps = List.of(r);
          seconds = s == null ? null : List.of(s);
        case IgnoreChoice():
          kind = DecisionKind.ignored;
          weight = null;
          reps = [];
          seconds = null;
      }

      final previous = repository.decision(logId);
      final decision = RecommendationDecision(
        id: previous?.id,
        exerciseLogId: logId,
        recommended: previous?.recommended ?? RecommendationSnapshot.of(recommendation),
        kind: kind,
        finalWeight: weight,
        finalReps: reps,
        finalSeconds: seconds,
        decidedAt: now.toUtc(),
      );
      repository.upsertDecision(decision);
      _applyDecision(decision, previous, log);
      return decision;
    });
  }

  /// Copies the loads (and reps as targets) of the last comparable session into the pending sets.
  /// The last session of a non-equivalent context is used only with `allowNonEquivalent`.
  void copyPreviousLoads(String logId, {bool allowNonEquivalent = false, required DateTime now}) {
    repository.transaction(() {
      _requireOpenLog(logId);
      final state = openExercise(logId, now: now);
      final source =
          state.recommendation.lastPerformance ??
          (allowNonEquivalent ? state.recommendation.nonEquivalentReference : null);
      if (source == null || source.sets.isEmpty) {
        throw const GymStoreError.notFound('No hay una sesión anterior para copiar.');
      }
      final measurement = state.log.snapshot.measurement;
      _ensureWorkingSets(source.sets.length, state.log);
      final working = _workingSets(state.log);
      for (var i = 0; i < working.length; i++) {
        final s = working[i];
        if (s.status != SetStatus.pending) continue;
        final from = source.sets[i < source.sets.length ? i : source.sets.length - 1];
        _setLoad(s, from.load, measurement);
        if (i < source.sets.length) {
          if (measurement == MeasurementType.duration) {
            s.targetSeconds = from.amount;
          } else {
            s.targetReps = from.amount;
          }
        }
        repository.upsertSetLog(s);
      }
    });
  }

  /// Recommendation for the *next* session (Home / routine preview / after finishing). Not frozen.
  Recommendation? previewRecommendation(String exerciseId, {ProgressionConfig? config, required DateTime now}) {
    final exercise = repository.exercise(exerciseId);
    if (exercise == null) return null;
    final labels = _history.lastUsedLabels(exerciseId);
    final context = ComparabilityContext(
      exerciseId: exerciseId,
      variantLabel: labels.variant,
      equipmentLabel: labels.equipment,
      loadMode: exercise.loadMode,
    );
    return _recommendation(context, exercise.measurement, config ?? _effectiveConfig(exercise), null, now);
  }

  ProgressionConfig _effectiveConfig(Exercise exercise) {
    final history = _history.exerciseHistory(exercise.id);
    final id = history.isEmpty ? null : history.first.log.routineExerciseId;
    if (id != null) {
      final override = repository.routineExercise(id)?.progressionOverride;
      if (override != null) return override;
    }
    return exercise.progression;
  }

  /// "Definir objetivo inicial": stored where the next session will read it, and used as today's
  /// target through a `modified` decision.
  RecommendationDecision setInitialTarget(
    String logId, {
    double? weight,
    List<int> reps = const [],
    List<int>? seconds,
    required DateTime now,
  }) {
    return repository.transaction(() {
      final log = _requireOpenLog(logId);
      if (weight != null) {
        final itemId = log.routineExerciseId;
        final item = itemId == null ? null : repository.routineExercise(itemId);
        final override = item?.progressionOverride;
        if (item != null && override != null) {
          override.initialWeight = LoadMath.normalized(weight);
          repository.upsertRoutineExercise(item..progressionOverride = override);
        } else {
          final exercise = repository.exercise(log.exerciseId);
          if (exercise != null) {
            exercise.progression.initialWeight = LoadMath.normalized(weight);
            repository.upsertExercise(exercise);
          }
        }
      }
      return decide(
        logId,
        ModifyChoice(weight: weight, reps: reps, seconds: seconds),
        now: now,
      );
    });
  }

  /// Preview for every exercise of a routine (routine preview / Home).
  List<(RoutineExercise, Exercise, Recommendation)> previewRecommendations(String routineId, {required DateTime now}) {
    final result = <(RoutineExercise, Exercise, Recommendation)>[];
    for (final item in repository.routineExercises(routineId)) {
      final exercise = repository.exercise(item.exerciseId);
      if (exercise == null || exercise.isArchived) continue;
      final rec = previewRecommendation(
        exercise.id,
        config: item.progressionOverride ?? exercise.progression,
        now: now,
      );
      if (rec != null) result.add((item, exercise, rec));
    }
    return result;
  }

  // MARK: - Sets

  SetLog addSet(String logId, {SetKind kind = SetKind.working}) {
    return repository.transaction(() {
      _requireOpenLog(logId);
      final sets = repository.setLogs(logId);
      final sameKind = sets.where((s) => s.kind == kind);
      final last = sameKind.isNotEmpty ? sameKind.last : (sets.isEmpty ? null : sets.last);
      final indexes = sets.map((s) => s.index);
      final set = SetLog(
        exerciseLogId: logId,
        index: (indexes.isEmpty ? -1 : indexes.reduce((a, b) => a > b ? a : b)) + 1,
        kind: kind,
        weight: kind == SetKind.warmup ? null : last?.weight,
        addedWeight: last?.addedWeight,
        assistance: last?.assistance,
      );
      repository.upsertSetLog(set);
      return set;
    });
  }

  /// Saves edited values. Negative values are rejected; unusual values are allowed (the UI warns).
  void updateSet(SetLog set) {
    repository.transaction(() {
      final existing = repository.setLog(set.id);
      if (existing == null) throw const GymStoreError.notFound('set');
      validate(set);
      final updated = set.copy()
        ..exerciseLogId = existing.exerciseLogId
        // Status only changes through completeSet / reopenSet (a stale edit can't un-complete a set).
        ..status = existing.status
        ..completedAt = existing.completedAt
        ..weight = set.weight == null ? null : LoadMath.normalized(set.weight!)
        ..addedWeight = set.addedWeight == null ? null : LoadMath.normalized(set.addedWeight!)
        ..assistance = set.assistance == null ? null : LoadMath.normalized(set.assistance!);
      repository.upsertSetLog(updated);
    });
  }

  /// Structural change: only while the session is open (finished history is never re-indexed).
  void removeSet(String setId) {
    repository.transaction(() {
      final set = repository.setLog(setId);
      if (set == null) throw const GymStoreError.notFound('set');
      _requireOpenLog(set.exerciseLogId);
      repository.deleteSetLog(setId);
      final remaining = repository.setLogs(set.exerciseLogId);
      for (var i = 0; i < remaining.length; i++) {
        if (remaining[i].index != i) repository.upsertSetLog(remaining[i]..index = i);
      }
    });
  }

  /// One-tap completion: missing reps/seconds are taken from the visible target. Records the real
  /// execution order of the exercise on its first completed set.
  SetLog completeSet(String setId, {required DateTime now}) {
    return repository.transaction(() {
      final set = repository.setLog(setId);
      if (set == null) throw const GymStoreError.notFound('set');
      final log = _requireOpenLog(set.exerciseLogId);
      switch (log.snapshot.measurement) {
        case MeasurementType.weightReps:
          set.reps ??= set.targetReps;
          if (set.weight == null || set.reps == null) throw const GymStoreError(GymStoreErrorKind.missingValues);
        case MeasurementType.bodyweightReps:
          set.reps ??= set.targetReps;
          if (set.reps == null) throw const GymStoreError(GymStoreErrorKind.missingValues);
        case MeasurementType.duration:
          set.seconds ??= set.targetSeconds;
          if (set.seconds == null) throw const GymStoreError(GymStoreErrorKind.missingValues);
      }
      validate(set);
      set
        ..status = SetStatus.completed
        ..completedAt = now.toUtc();
      repository.upsertSetLog(set);

      if (log.executionOrder == null) {
        final used = repository.exerciseLogsOfSession(log.sessionId).map((l) => l.executionOrder).whereType<int>();
        log.executionOrder = (used.isEmpty ? -1 : used.reduce((a, b) => a > b ? a : b)) + 1;
        repository.upsertExerciseLog(log);
      }
      final session = repository.session(log.sessionId);
      if (session != null) repository.upsertSession(session..updatedAt = now.toUtc());
      return set;
    });
  }

  /// After completing a set: inside a superset round, go straight to the next exercise of the
  /// group (no rest); otherwise rest for the exercise's (or the global) rest time.
  RestAdvice restAdvice(String setId) {
    final set = repository.setLog(setId);
    final log = set == null ? null : repository.exerciseLog(set.exerciseLogId);
    if (set == null || log == null) return RestAdvice(repository.settings().defaultRestSeconds, null);
    final rest = log.restSeconds ?? repository.settings().defaultRestSeconds;
    // Warm-ups are not part of the superset round: plain rest, stay on this exercise.
    final group = log.supersetGroup;
    if (set.kind != SetKind.working || group == null) return RestAdvice(rest, null);
    final members = repository.exerciseLogsOfSession(log.sessionId).where((l) => l.supersetGroup == group).toList();
    final index = members.indexWhere((l) => l.id == log.id);
    if (index < 0) return RestAdvice(rest, null);
    // Next member (cyclically after this one) that still has pending working sets.
    for (var offset = 1; offset < (members.length > 1 ? members.length : 1); offset++) {
      final candidate = members[(index + offset) % members.length];
      final pending = repository
          .setLogs(candidate.id)
          .any((s) => s.kind == SetKind.working && s.status == SetStatus.pending);
      if (!pending) continue;
      // Wrapping back to the start of the group ends the round: rest first.
      final wraps = index + offset >= members.length;
      return RestAdvice(wraps ? rest : null, candidate.id);
    }
    return RestAdvice(rest, null);
  }

  void reopenSet(String setId) {
    repository.transaction(() {
      final set = repository.setLog(setId);
      if (set == null) throw const GymStoreError.notFound('set');
      _requireOpenLog(set.exerciseLogId);
      repository.upsertSetLog(
        set
          ..status = SetStatus.pending
          ..completedAt = null,
      );
    });
  }

  // MARK: - Internals

  Recommendation computeRecommendation(ExerciseLog log, DateTime now) =>
      _recommendation(log.context, log.snapshot.measurement, log.configSnapshot, log.sessionId, now);

  Recommendation _recommendation(
    ComparabilityContext context,
    MeasurementType measurement,
    ProgressionConfig config,
    String? excludingSessionId,
    DateTime now,
  ) {
    final settings = repository.settings();
    return ProgressionEngine.recommend(
      ProgressionInput(
        context: context,
        measurement: measurement,
        config: config,
        history: _history.performances(context.exerciseId),
        links: repository.comparabilityLinks(),
        now: now.toUtc(),
        excludingSessionId: excludingSessionId,
        timeZone: timeZone,
        firstWeekday: settings.firstWeekday,
        locale: locale.identifier,
        oneRepMax: settings.oneRepMax,
      ),
    );
  }

  ExerciseLog _createLog(
    WorkoutSession session,
    Exercise exercise,
    ProgressionConfig config, {
    String? routineExerciseId,
    int? restSeconds,
    required String notes,
    required int order,
    int? supersetGroup,
  }) {
    final labels = _history.lastUsedLabels(exercise.id);
    final sanitized = config.sanitized();
    final log = ExerciseLog(
      sessionId: session.id,
      exerciseId: exercise.id,
      routineExerciseId: routineExerciseId,
      supersetGroup: supersetGroup,
      snapshot: ExerciseSnapshot.of(exercise),
      configSnapshot: sanitized,
      variantLabel: labels.variant,
      equipmentLabel: labels.equipment,
      plannedOrder: order,
      restSeconds: restSeconds,
      notes: notes,
    );
    repository.upsertExerciseLog(log);
    for (var i = 0; i < sanitized.targetSets; i++) {
      repository.upsertSetLog(SetLog(exerciseLogId: log.id, index: i));
    }
    return log;
  }

  ExerciseLogState _state(ExerciseLog log) =>
      ExerciseLogState(log, repository.setLogs(log.id), log.frozenRecommendation!, repository.decision(log.id));

  List<SetLog> _workingSets(ExerciseLog log) =>
      repository.setLogs(log.id).where((s) => s.kind == SetKind.working).toList();

  void _ensureWorkingSets(int count, ExerciseLog log) {
    final existing = _workingSets(log).length;
    for (var i = existing; i < count; i++) {
      addSet(log.id);
    }
  }

  void _applyDecision(RecommendationDecision decision, RecommendationDecision? previous, ExerciseLog log) {
    final measurement = log.snapshot.measurement;
    switch (decision.kind) {
      case DecisionKind.accepted:
      case DecisionKind.modified:
        final seconds = decision.finalSeconds;
        final count = decision.finalReps.length > (seconds?.length ?? 0)
            ? decision.finalReps.length
            : (seconds?.length ?? 0);
        _ensureWorkingSets(count, log);
        final working = _workingSets(log);
        for (var i = 0; i < working.length; i++) {
          final s = working[i];
          if (s.status != SetStatus.pending) continue;
          final w = decision.finalWeight;
          if (w != null) _setLoad(s, w, measurement);
          s.targetReps = i < decision.finalReps.length ? decision.finalReps[i] : null;
          s.targetSeconds = seconds != null && i < seconds.length ? seconds[i] : null;
          repository.upsertSetLog(s);
        }
      case DecisionKind.ignored:
        for (final s in _workingSets(log)) {
          if (s.status != SetStatus.pending) continue;
          s
            ..targetReps = null
            ..targetSeconds = null;
          final w = previous?.finalWeight;
          if (w != null && previous!.kind != DecisionKind.ignored && _loadMatches(s, w, measurement)) {
            _clearLoad(s, measurement);
          }
          repository.upsertSetLog(s);
        }
    }
  }

  static void _setLoad(SetLog set, double load, MeasurementType measurement) {
    switch (measurement) {
      case MeasurementType.weightReps:
      case MeasurementType.duration:
        set.weight = LoadMath.normalized(load);
      case MeasurementType.bodyweightReps:
        final k = LoadMath.key(load);
        set.addedWeight = k > 0 ? LoadMath.normalized(load) : null;
        set.assistance = k < 0 ? LoadMath.normalized(-load) : null;
    }
  }

  static bool _loadMatches(SetLog set, double load, MeasurementType measurement) => switch (measurement) {
    MeasurementType.weightReps || MeasurementType.duration => set.weight != null && LoadMath.isEqual(set.weight!, load),
    MeasurementType.bodyweightReps => LoadMath.isEqual(set.performed.netAddedLoad, load),
  };

  static void _clearLoad(SetLog set, MeasurementType measurement) {
    switch (measurement) {
      case MeasurementType.weightReps:
      case MeasurementType.duration:
        set.weight = null;
      case MeasurementType.bodyweightReps:
        set
          ..addedWeight = null
          ..assistance = null;
    }
  }

  void _closePause(WorkoutSession session, DateTime now) {
    for (var i = session.pauses.length - 1; i >= 0; i--) {
      if (session.pauses[i].end == null) {
        session.pauses[i].end = now.toUtc();
        return;
      }
    }
  }

  WorkoutSession _openSession(String id) {
    final session = repository.session(id);
    if (session == null) throw const GymStoreError.notFound('session');
    if (!session.isOpen) throw const GymStoreError(GymStoreErrorKind.sessionNotOpen);
    return session;
  }

  ExerciseLog _requireLog(String id) {
    final log = repository.exerciseLog(id);
    if (log == null) throw const GymStoreError.notFound('exerciseLog');
    return log;
  }

  /// For changes that only make sense during the workout: refused once the session is finished.
  ExerciseLog _requireOpenLog(String id) {
    final log = _requireLog(id);
    if (repository.session(log.sessionId)?.isOpen != true) throw const GymStoreError(GymStoreErrorKind.sessionNotOpen);
    return log;
  }

  static String? cleanLabel(String? label) {
    final trimmed = swiftTrim(label ?? '');
    return trimmed.isEmpty ? null : trimmed;
  }

  static void validate(SetLog set) {
    final issues = SetValidator.validate(
      weight: set.weight,
      reps: set.reps,
      seconds: set.seconds,
      rir: set.rir,
      rpe: set.rpe,
    );
    for (final issue in issues) {
      if (issue.isError) throw GymStoreError.invalidValue(issue.message);
    }
    final a = set.addedWeight;
    if (a != null && !(a.isFinite && a >= 0)) {
      throw const GymStoreError.invalidValue('El lastre no puede ser negativo.');
    }
    final s = set.assistance;
    if (s != null && !(s.isFinite && s >= 0)) {
      throw const GymStoreError.invalidValue('La asistencia no puede ser negativa.');
    }
  }
}
