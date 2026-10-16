/// Read-side mapping from records to GymCore inputs (port of HistoryService.swift). No business
/// rules: it only translates.
library;

import 'package:gym_core/gym_core.dart';

import 'records.dart';
import 'repository.dart';

/// One exercise as performed in a past session, for history screens.
class ExerciseHistoryEntry {
  final WorkoutSession session;
  final ExerciseLog log;
  final List<SetLog> sets;
  final RecommendationDecision? decision;
  final ExercisePerformance performance;
  const ExerciseHistoryEntry(this.session, this.log, this.sets, this.decision, this.performance);

  String get id => log.id;
}

/// One finished session for the history list.
class SessionSummary {
  final WorkoutSession session;
  final List<String> exerciseNames;
  final int effectiveSets;

  /// External load volume (kg), per section 8.1 (per-side exercises counted as total).
  final double volume;

  /// Seconds, excluding pauses.
  final double duration;
  const SessionSummary(this.session, this.exerciseNames, this.effectiveSets, this.volume, this.duration);
}

class HistoryService {
  final GymRepository repository;
  const HistoryService(this.repository);

  /// Every log of the exercise, in any context and any session status. The engine and the metrics
  /// decide what is comparable / valid.
  List<ExercisePerformance> performances(String exerciseId) {
    final logs = repository.exerciseLogsOfExercise(exerciseId);
    final sessions = repository.sessionsById(logs.map((l) => l.sessionId).toSet());
    final sets = repository.setLogsOfLogs(logs.map((l) => l.id).toList());
    return [
      for (final log in logs)
        if (sessions[log.sessionId] != null) performanceOf(log, sessions[log.sessionId]!, sets[log.id] ?? const []),
    ];
  }

  ExercisePerformance performanceOf(ExerciseLog log, WorkoutSession session, [List<SetLog>? sets]) =>
      ExercisePerformance(
        sessionId: session.id,
        exerciseLogId: log.id,
        sessionStart: session.startedAt,
        sessionStatus: session.status,
        isAtypical: session.isAtypical || log.isAtypical,
        context: log.context,
        measurement: log.snapshot.measurement,
        sets: (sets ?? repository.setLogs(log.id)).map((s) => s.performed).toList(),
      );

  /// Completed sessions of the exercise, newest first, with their sets and decisions.
  List<ExerciseHistoryEntry> exerciseHistory(String exerciseId) {
    final entries = <ExerciseHistoryEntry>[];
    for (final log in repository.exerciseLogsOfExercise(exerciseId)) {
      final session = repository.session(log.sessionId);
      if (session == null || session.status != SessionStatus.completed) continue;
      entries.add(
        ExerciseHistoryEntry(
          session,
          log,
          repository.setLogs(log.id),
          repository.decision(log.id),
          performanceOf(log, session),
        ),
      );
    }
    return stableSorted(entries, (a, b) {
      final c = b.session.startedAt.compareTo(a.session.startedAt);
      return c != 0 ? c : a.log.id.compareTo(b.log.id);
    });
  }

  /// Completed sessions, newest first (history list). Discarded/open sessions are not history.
  List<SessionSummary> completedSessionSummaries({int? limit}) {
    final completed = repository.sessions().where((s) => s.status == SessionStatus.completed).toList().reversed;
    final selected = limit == null ? completed.toList() : completed.take(limit).toList();
    final bodyweight = repository.settings().bodyweightKg;
    return selected.map((session) {
      const maxInt = 0x7FFFFFFFFFFFFFFF;
      final logs = stableSorted(repository.exerciseLogsOfSession(session.id), (ExerciseLog a, ExerciseLog b) {
        final ea = a.executionOrder ?? maxInt, eb = b.executionOrder ?? maxInt;
        return ea != eb ? ea.compareTo(eb) : a.plannedOrder.compareTo(b.plannedOrder);
      });
      final sets = repository.setLogsOfLogs(logs.map((l) => l.id).toList());
      var effective = 0;
      var volume = 0.0;
      for (final log in logs) {
        final v = Volume.of(performanceOf(log, session, sets[log.id] ?? const []), bodyweight: bodyweight);
        effective += v.effectiveSets;
        volume += v.total;
      }
      return SessionSummary(
        session,
        logs.map((l) => l.snapshot.name).toList(),
        effective,
        LoadMath.normalized(volume),
        session.elapsed(session.endedAt ?? session.startedAt),
      );
    }).toList();
  }

  /// Exercises with at least one completed session.
  Set<String> exerciseIdsWithCompletedHistory() => {
    for (final session in repository.sessions())
      if (session.status == SessionStatus.completed)
        for (final log in repository.exerciseLogsOfSession(session.id)) log.exerciseId,
  };

  /// Digest of every session (consistency metrics).
  List<SessionDigest> sessionDigests() => repository.sessions().map((session) {
    var effective = 0;
    for (final log in repository.exerciseLogsOfSession(session.id)) {
      effective += repository.setLogs(log.id).where((s) => s.performed.isEffective(log.snapshot.measurement)).length;
    }
    return SessionDigest(
      id: session.id,
      start: session.startedAt,
      status: session.status,
      effectiveSets: effective,
      routineId: session.routineId,
    );
  }).toList();

  /// Muscle work of completed sessions starting in `interval` (muscles from the log snapshot).
  List<MuscleWork> muscleWork(DateInterval interval, {String? routineId}) => [
    for (final session in repository.sessions())
      if (session.status == SessionStatus.completed &&
          interval.containsHalfOpen(session.startedAt) &&
          (routineId == null || session.routineId == routineId))
        for (final log in repository.exerciseLogsOfSession(session.id))
          MuscleWork(performanceOf(log, session), log.snapshot.primaryMuscles, log.snapshot.secondaryMuscles),
  ];

  /// Labels of the most recent completed log of this exercise (default context for a new log).
  ({String? variant, String? equipment}) lastUsedLabels(String exerciseId) {
    ExerciseLog? best;
    DateTime? bestStart;
    for (final log in repository.exerciseLogsOfExercise(exerciseId)) {
      final s = repository.session(log.sessionId);
      if (s == null || s.status != SessionStatus.completed) continue;
      // Swift `max(by:)`: keeps the first maximum, so replace only when strictly greater.
      if (best == null ||
          s.startedAt.isAfter(bestStart!) ||
          (s.startedAt.compareTo(bestStart) == 0 && best.id.compareTo(log.id) < 0)) {
        best = log;
        bestStart = s.startedAt;
      }
    }
    return (variant: best?.variantLabel, equipment: best?.equipmentLabel);
  }
}
