/// Routine templates and exercise library (port of RoutineService.swift). Editing a template never
/// alters past sessions (logs keep snapshots).
library;

import 'package:gym_core/gym_core.dart';

import 'catalog.dart';
import 'records.dart';
import 'repository.dart';

class RoutineService {
  final GymRepository repository;
  const RoutineService(this.repository);

  RoutineTemplate createRoutine(String name, {String notes = '', required DateTime now}) {
    final clean = swiftTrim(name);
    if (clean.isEmpty) throw const GymStoreError.invalidValue('El nombre no puede estar vacío.');
    final orders = repository.routines().map((r) => r.sortOrder);
    final order = (orders.isEmpty ? -1 : orders.reduce((a, b) => a > b ? a : b)) + 1;
    final routine = RoutineTemplate(name: clean, sortOrder: order, notes: notes, createdAt: now);
    repository.upsertRoutine(routine);
    return routine;
  }

  void updateRoutine(RoutineTemplate routine) {
    if (repository.routine(routine.id) == null) throw const GymStoreError.notFound('routine');
    if (swiftTrim(routine.name).isEmpty) throw const GymStoreError.invalidValue('El nombre no puede estar vacío.');
    repository.upsertRoutine(routine);
  }

  RoutineTemplate duplicateRoutine(String id, {required DateTime now}) {
    return repository.transaction(() {
      final source = repository.routine(id);
      if (source == null) throw const GymStoreError.notFound('routine');
      final copy = createRoutine('${source.name} (copia)', notes: source.notes, now: now);
      for (final item in repository.routineExercises(id)) {
        final dup = item.copy()
          ..id = newUuid()
          ..routineId = copy.id;
        repository.upsertRoutineExercise(dup);
      }
      return copy;
    });
  }

  void setArchived(String routineId, bool archived) {
    final routine = repository.routine(routineId);
    if (routine == null) throw const GymStoreError.notFound('routine');
    repository.upsertRoutine(routine..isArchived = archived);
  }

  /// Hard delete only when no session used the routine; otherwise archive instead.
  void deleteRoutine(String id) => repository.deleteRoutine(id);

  void reorderRoutines(List<String> orderedIds) {
    repository.transaction(() {
      for (var i = 0; i < orderedIds.length; i++) {
        final routine = repository.routine(orderedIds[i]);
        if (routine == null || routine.sortOrder == i) continue;
        repository.upsertRoutine(routine..sortOrder = i);
      }
    });
  }

  // MARK: Exercises in a routine

  RoutineExercise addExercise(
    String routineId,
    String exerciseId, {
    ProgressionConfig? override,
    int? restSeconds,
    String notes = '',
  }) {
    if (repository.routine(routineId) == null) throw const GymStoreError.notFound('routine');
    if (repository.exercise(exerciseId) == null) throw const GymStoreError.notFound('exercise');
    final orders = repository.routineExercises(routineId).map((r) => r.sortOrder);
    final order = (orders.isEmpty ? -1 : orders.reduce((a, b) => a > b ? a : b)) + 1;
    final item = RoutineExercise(
      routineId: routineId,
      exerciseId: exerciseId,
      sortOrder: order,
      restSeconds: restSeconds,
      notes: notes,
      progressionOverride: override?.sanitized(),
    );
    repository.upsertRoutineExercise(item);
    return item;
  }

  void updateRoutineExercise(RoutineExercise item) {
    if (repository.routineExercise(item.id) == null) throw const GymStoreError.notFound('routineExercise');
    final clean = item.copy()..progressionOverride = item.progressionOverride?.sanitized();
    repository.upsertRoutineExercise(clean);
  }

  void removeRoutineExercise(String id) => repository.deleteRoutineExercise(id);

  RoutineExercise duplicateRoutineExercise(String id) {
    return repository.transaction(() {
      final item = repository.routineExercise(id);
      if (item == null) throw const GymStoreError.notFound('routineExercise');
      final dup = item.copy()
        ..id = newUuid()
        ..sortOrder = item.sortOrder + 1;
      // Shift the following items down to make room right after the original.
      for (final other in repository.routineExercises(item.routineId)) {
        if (other.sortOrder > item.sortOrder) repository.upsertRoutineExercise(other..sortOrder += 1);
      }
      repository.upsertRoutineExercise(dup);
      return dup;
    });
  }

  void moveExercises(String routineId, List<String> orderedIds) {
    repository.transaction(() {
      for (var i = 0; i < orderedIds.length; i++) {
        final item = repository.routineExercise(orderedIds[i]);
        if (item == null || item.routineId != routineId || item.sortOrder == i) continue;
        repository.upsertRoutineExercise(item..sortOrder = i);
      }
    });
  }

  /// Groups exercises as a superset / biset (null ungroups).
  void setSuperset(List<String> ids, int? group) {
    repository.transaction(() {
      for (final id in ids) {
        final item = repository.routineExercise(id);
        if (item == null) continue;
        repository.upsertRoutineExercise(item..supersetGroup = group);
      }
    });
  }

  ProgressionConfig? effectiveConfig(RoutineExercise item) =>
      item.progressionOverride ?? repository.exercise(item.exerciseId)?.progression;

  /// Creates an editable routine from a preset. Exercises missing from the catalog are skipped.
  RoutineTemplate createFromPreset(RoutinePreset preset, {required DateTime now}) {
    return repository.transaction(() {
      final byCatalogId = <String, Exercise>{};
      for (final e in repository.exercises()) {
        final c = e.catalogId;
        if (c != null) byCatalogId.putIfAbsent(c, () => e);
      }
      final routine = createRoutine(preset.name, notes: preset.notes, now: now);
      for (final entry in preset.exercises) {
        final exercise = byCatalogId[entry.catalogId];
        if (exercise == null) continue;
        final config = exercise.progression.copy()..targetSets = entry.sets;
        if (exercise.measurement == MeasurementType.duration) {
          config
            ..secondsMin = entry.repMin
            ..secondsMax = entry.repMax;
        } else {
          config
            ..repMin = entry.repMin
            ..repMax = entry.repMax;
        }
        addExercise(routine.id, exercise.id, override: config, restSeconds: entry.restSeconds);
      }
      return routine;
    });
  }
}

/// Exercise library management. Catalog updates never lose user exercises or the user's edits to
/// catalog exercises' progression criteria.
class ExerciseCatalogService {
  final GymRepository repository;
  const ExerciseCatalogService(this.repository);

  Exercise createCustomExercise({
    required String name,
    required MeasurementType measurement,
    required Equipment equipment,
    required LoadMode loadMode,
    required List<MuscleGroup> primaryMuscles,
    List<MuscleInvolvement> secondaryMuscles = const [],
    double increment = 2.5,
    List<double>? availableWeights,
    ProgressionConfig? progression,
  }) {
    final clean = swiftTrim(name);
    if (clean.isEmpty) throw const GymStoreError.invalidValue('El nombre no puede estar vacío.');
    final config = (progression?.copy() ?? ProgressionConfig(increment: increment, availableWeights: availableWeights))
      ..increment = increment
      ..availableWeights = availableWeights;
    final exercise = Exercise(
      id: newUuid(),
      name: clean,
      measurement: measurement,
      equipment: equipment,
      loadMode: loadMode,
      primaryMuscles: List.of(primaryMuscles),
      secondaryMuscles: List.of(secondaryMuscles),
      defaultIncrement: increment,
      availableWeights: availableWeights,
      progression: config.sanitized(),
      isCustom: true,
    );
    repository.upsertExercise(exercise);
    return exercise;
  }

  /// Catalog edits never touch past logs (they hold snapshots).
  void updateExercise(Exercise exercise) {
    if (repository.exercise(exercise.id) == null) throw const GymStoreError.notFound('exercise');
    final clean = exercise.copy()..progression = exercise.progression.sanitized();
    repository.upsertExercise(clean);
  }

  void updateProgression(String exerciseId, ProgressionConfig config) {
    final exercise = repository.exercise(exerciseId);
    if (exercise == null) throw const GymStoreError.notFound('exercise');
    repository.upsertExercise(exercise..progression = config.sanitized());
  }

  void setArchived(String exerciseId, bool archived) {
    final exercise = repository.exercise(exerciseId);
    if (exercise == null) throw const GymStoreError.notFound('exercise');
    repository.upsertExercise(exercise..isArchived = archived);
  }

  /// Hard delete only without history (throws hasHistory; archive instead).
  void deleteExercise(String id) => repository.deleteExercise(id);

  /// Idempotent catalog seeding/update: new entries inserted; existing catalog exercises get
  /// catalog fields refreshed while progression edits and the archive flag are kept. Custom
  /// exercises are never touched.
  ({int inserted, int updated}) seed(ExerciseCatalog catalog) {
    return repository.transaction(() {
      var inserted = 0, updated = 0;
      String muscles(List<MuscleGroup> m) => m.map((e) => e.name).join(',');
      String secondary(List<MuscleInvolvement> m) => canonicalJson(m.map((e) => e.toJson()).toList());
      for (final entry in catalog.exercises) {
        final existing = repository.exercise(entry.uuid);
        if (existing != null) {
          if (existing.isCustom) continue;
          final fresh = entry.makeExercise();
          if (existing.name != fresh.name ||
              muscles(existing.primaryMuscles) != muscles(fresh.primaryMuscles) ||
              secondary(existing.secondaryMuscles) != secondary(fresh.secondaryMuscles) ||
              existing.equipment != fresh.equipment) {
            existing
              ..name = fresh.name
              ..primaryMuscles = fresh.primaryMuscles
              ..secondaryMuscles = fresh.secondaryMuscles
              ..equipment = fresh.equipment
              ..catalogId = fresh.catalogId;
            repository.upsertExercise(existing);
            updated++;
          }
        } else {
          repository.upsertExercise(entry.makeExercise());
          inserted++;
        }
      }
      return (inserted: inserted, updated: updated);
    });
  }
}
