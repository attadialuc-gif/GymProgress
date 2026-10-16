/// Export / import / backup on top of [GymDatabase] (port of ExportService.swift). Same JSON
/// contract as iOS (`schemaVersion`): an iPhone export imports here and vice versa. Import
/// validates first and merges by id: re-importing the same file never duplicates anything.
library;

import 'dart:convert';

import 'package:gym_core/gym_core.dart';

import 'records.dart';
import 'repository.dart';

class ImportSummary {
  /// New records added.
  final int inserted;

  /// Records in the file that differ from the local ones: the local version is kept.
  final int conflicts;

  /// Records identical to the local ones.
  final int unchanged;
  const ImportSummary(this.inserted, this.conflicts, this.unchanged);
}

class ExportService {
  final GymRepository repository;
  const ExportService(this.repository);

  String exportJson({required DateTime now}) {
    repository.validateIntegrity();
    final db = repository.snapshot()..exportedAt = now.toUtc();
    return db.encode();
  }

  /// Decodes and validates without touching the repository.
  GymDatabase validate(String text) {
    final GymDatabase db;
    try {
      db = GymDatabase.fromJson(asJson(jsonDecode(text)));
    } catch (_) {
      throw const GymStoreError.invalidImport('El archivo no es una copia válida de GymProgress.');
    }
    if (db.schemaVersion < 1 || db.schemaVersion > gymSchemaVersion) {
      throw GymStoreError(GymStoreErrorKind.unsupportedSchemaVersion, '${db.schemaVersion}');
    }
    final current = repository.snapshot();
    final sessionIds = {...db.sessions.map((s) => s.id), ...current.sessions.map((s) => s.id)};
    final logIds = {...db.exerciseLogs.map((l) => l.id), ...current.exerciseLogs.map((l) => l.id)};
    final exerciseIds = {...db.exercises.map((e) => e.id), ...current.exercises.map((e) => e.id)};
    final routineIds = {...db.routines.map((r) => r.id), ...current.routines.map((r) => r.id)};

    for (final l in db.exerciseLogs) {
      if (!sessionIds.contains(l.sessionId)) {
        throw GymStoreError.invalidImport('Registro de ejercicio sin sesión: ${l.id}');
      }
    }
    for (final l in db.exerciseLogs) {
      if (!exerciseIds.contains(l.exerciseId)) {
        throw GymStoreError.invalidImport('Registro de un ejercicio inexistente: ${l.id}');
      }
    }
    final decisionLogs = db.decisions.map((d) => d.exerciseLogId).toList();
    if (decisionLogs.toSet().length != decisionLogs.length) {
      throw const GymStoreError.invalidImport('Hay más de una decisión para el mismo ejercicio de una sesión.');
    }
    for (final s in db.setLogs) {
      final a = s.addedWeight;
      if (a != null && !(a.isFinite && a >= 0)) throw GymStoreError.invalidImport('Serie con lastre inválido: ${s.id}');
      final b = s.assistance;
      if (b != null && !(b.isFinite && b >= 0)) {
        throw GymStoreError.invalidImport('Serie con asistencia inválida: ${s.id}');
      }
    }
    for (final s in db.setLogs) {
      if (!logIds.contains(s.exerciseLogId)) throw GymStoreError.invalidImport('Serie sin ejercicio: ${s.id}');
    }
    for (final d in db.decisions) {
      if (!logIds.contains(d.exerciseLogId)) throw GymStoreError.invalidImport('Decisión sin ejercicio: ${d.id}');
    }
    for (final r in db.routineExercises) {
      if (!routineIds.contains(r.routineId) || !exerciseIds.contains(r.exerciseId)) {
        throw GymStoreError.invalidImport('Ejercicio de rutina inválido: ${r.id}');
      }
    }
    for (final s in db.setLogs) {
      final issues = SetValidator.validate(weight: s.weight, reps: s.reps, seconds: s.seconds, rir: s.rir, rpe: s.rpe);
      if (issues.any((i) => i.isError)) throw GymStoreError.invalidImport('Serie con valores inválidos: ${s.id}');
    }
    return db;
  }

  /// Validates, then inserts only what is new (all-or-nothing). Local records are never
  /// overwritten. Refused while a local workout is open and the file has a different open workout.
  /// Settings are imported only into a store without history.
  ImportSummary importJson(String text) {
    return repository.transaction(() {
      final incoming = validate(text);
      final before = repository.snapshot();
      final localIds = before.sessions.map((s) => s.id).toSet();
      final localOpen = before.sessions.where((s) => s.isOpen).map((s) => s.id).toSet();
      final incomingOpen = incoming.sessions
          .where((s) => s.isOpen && !localOpen.contains(s.id) && !localIds.contains(s.id))
          .toList();
      if (incomingOpen.isNotEmpty && (localOpen.isNotEmpty || incomingOpen.length > 1)) {
        throw const GymStoreError.invalidImport(
          'Terminá o descartá el entrenamiento en curso antes de importar una copia que tiene otro entrenamiento abierto.',
        );
      }
      final filtered = withoutChildrenOfLocalSessions(incoming, before);
      // Children of local sessions are never inserted: they count as unchanged or conflicts.
      final summary = diff(before, filtered);
      final keptLogs = filtered.exerciseLogs.map((l) => l.id).toSet();
      final keptSets = filtered.setLogs.map((s) => s.id).toSet();
      final keptDecisions = filtered.decisions.map((d) => d.exerciseLogId).toSet();
      final dropped = GymDatabase(
        exerciseLogs: incoming.exerciseLogs.where((l) => !keptLogs.contains(l.id)).toList(),
        setLogs: incoming.setLogs.where((s) => !keptSets.contains(s.id)).toList(),
        decisions: incoming.decisions.where((d) => !keptDecisions.contains(d.exerciseLogId)).toList(),
      );
      final droppedDiff = diff(before, dropped);
      final isEmptyStore = before.sessions.isEmpty && before.routines.isEmpty;
      repository.merge(filtered, includeSettings: isEmptyStore);
      return ImportSummary(
        summary.inserted,
        summary.conflicts + droppedDiff.conflicts + droppedDiff.inserted,
        summary.unchanged + droppedDiff.unchanged,
      );
    });
  }

  /// A session that already exists locally is the local truth as a whole.
  static GymDatabase withoutChildrenOfLocalSessions(GymDatabase incoming, GymDatabase local) {
    final localSessions = local.sessions.map((s) => s.id).toSet();
    final logs = incoming.exerciseLogs.where((l) => !localSessions.contains(l.sessionId)).toList();
    final imported = logs.map((l) => l.id).toSet();
    return GymDatabase(
      schemaVersion: incoming.schemaVersion,
      exportedAt: incoming.exportedAt,
      exercises: incoming.exercises,
      routines: incoming.routines,
      routineExercises: incoming.routineExercises,
      schedule: incoming.schedule,
      sessions: incoming.sessions,
      exerciseLogs: logs,
      setLogs: incoming.setLogs.where((s) => imported.contains(s.exerciseLogId)).toList(),
      decisions: incoming.decisions.where((d) => imported.contains(d.exerciseLogId)).toList(),
      comparabilityLinks: incoming.comparabilityLinks,
      goals: incoming.goals,
      settings: incoming.settings,
    );
  }

  /// CSV of every set of completed sessions (one row per set). RFC 4180, comma separator, dot
  /// decimals and ISO-8601 dates.
  String exportSetsCsv() {
    final rows = [
      'session_id,session_start,routine,exercise,measurement,load_mode,variant,equipment,set_index,set_kind,status,weight_kg,reps,seconds,added_kg,assistance_kg,rir,rpe,atypical',
    ];
    for (final session in repository.sessions()) {
      if (session.status != SessionStatus.completed) continue;
      for (final log in repository.exerciseLogsOfSession(session.id)) {
        for (final set in repository.setLogs(log.id)) {
          final fields = [
            session.id,
            iso8601(session.startedAt),
            csvText(session.routineNameSnapshot ?? ''),
            csvText(log.snapshot.name),
            log.snapshot.measurement.name,
            // weight_kg is per side when load_mode is perSide.
            log.snapshot.loadMode.name,
            csvText(log.variantLabel ?? ''),
            csvText(log.equipmentLabel ?? ''),
            '${set.index}',
            set.kind.name,
            set.status.name,
            csvNumber(set.weight),
            set.reps?.toString() ?? '',
            set.seconds?.toString() ?? '',
            csvNumber(set.addedWeight),
            csvNumber(set.assistance),
            csvNumber(set.rir),
            csvNumber(set.rpe),
            (session.isAtypical || log.isAtypical) ? '1' : '0',
          ];
          rows.add(fields.map(csvEscape).join(','));
        }
      }
    }
    return '${rows.join('\n')}\n';
  }

  /// `ISO8601DateFormatter` default: UTC, whole seconds.
  static String iso8601(DateTime d) {
    final u = d.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }

  /// Up to 3 decimals, no grouping, dot separator (Swift `en_US_POSIX` number style).
  static String csvNumber(double? v) =>
      v == null ? '' : GymFormat.number(v, locale: GymLocale.posix, maxFractionDigits: 3);

  /// User-typed text: a leading =, +, -, @ (or tab/CR) would run as a spreadsheet formula.
  static String csvText(String value) {
    if (value.isEmpty) return value;
    return '=+-@\t\r'.contains(String.fromCharCode(value.runes.first)) ? "'$value" : value;
  }

  static String csvEscape(String field) {
    if (!field.contains(',') && !field.contains('"') && !field.contains('\n') && !field.contains('\r')) return field;
    return '"${field.replaceAll('"', '""')}"';
  }

  static ImportSummary diff(GymDatabase before, GymDatabase incoming) {
    var inserted = 0, conflicts = 0, unchanged = 0;
    void count<T>(List<T> old, List<T> fresh, String Function(T) id, Json Function(T) json) {
      final existing = <String, T>{};
      for (final o in old) {
        existing.putIfAbsent(id(o), () => o);
      }
      for (final item in fresh) {
        final e = existing[id(item)];
        if (e == null) {
          inserted++;
        } else if (canonicalJson(json(e)) == canonicalJson(json(item))) {
          unchanged++;
        } else {
          conflicts++;
        }
      }
    }

    count<Exercise>(before.exercises, incoming.exercises, (e) => e.id, (e) => e.toJson());
    count<RoutineTemplate>(before.routines, incoming.routines, (e) => e.id, (e) => e.toJson());
    count<RoutineExercise>(before.routineExercises, incoming.routineExercises, (e) => e.id, (e) => e.toJson());
    count<ScheduleEntry>(before.schedule, incoming.schedule, (e) => e.id, (e) => e.toJson());
    count<WorkoutSession>(before.sessions, incoming.sessions, (e) => e.id, (e) => e.toJson());
    count<ExerciseLog>(before.exerciseLogs, incoming.exerciseLogs, (e) => e.id, (e) => e.toJson());
    count<SetLog>(before.setLogs, incoming.setLogs, (e) => e.id, (e) => e.toJson());
    // Decisions are unique per exercise log: compare by log id.
    count<RecommendationDecision>(before.decisions, incoming.decisions, (e) => e.exerciseLogId, (e) => e.toJson());
    count<ComparabilityLink>(before.comparabilityLinks, incoming.comparabilityLinks, (e) => e.id, (e) => e.toJson());
    count<Goal>(before.goals, incoming.goals, (e) => e.id, (e) => e.toJson());
    return ImportSummary(inserted, conflicts, unchanged);
  }
}
