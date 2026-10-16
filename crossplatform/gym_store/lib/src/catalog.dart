/// Bundled exercise library and routine presets (port of Catalog.swift). The library is the same
/// `exercises.json` shipped with the iOS app (fixed UUIDs and catalog ids), embedded at build time
/// in `catalog_data.g.dart` (regenerate with `dart run tool/gen_catalog.dart`).
library;

import 'dart:convert';

import 'package:gym_core/gym_core.dart';

import 'catalog_data.g.dart';

class CatalogSecondary {
  final MuscleGroup muscle;
  final double? factor;
  const CatalogSecondary(this.muscle, this.factor);
}

class CatalogEntry {
  final String uuid;
  final String catalogId;
  final String name;
  final MeasurementType measurement;
  final Equipment equipment;
  final LoadMode loadMode;
  final List<MuscleGroup> primary;
  final List<CatalogSecondary> secondary;
  final double increment;
  final int? repMin;
  final int? repMax;
  final int? restSeconds;

  const CatalogEntry({
    required this.uuid,
    required this.catalogId,
    required this.name,
    required this.measurement,
    required this.equipment,
    required this.loadMode,
    required this.primary,
    required this.secondary,
    required this.increment,
    this.repMin,
    this.repMax,
    this.restSeconds,
  });

  factory CatalogEntry.fromJson(Json j) => CatalogEntry(
    uuid: uuidFromJson(j['uuid']),
    catalogId: j['catalogId'] as String,
    name: j['name'] as String,
    measurement: enumFromName(MeasurementType.values, j['measurement']),
    equipment: enumFromName(Equipment.values, j['equipment']),
    loadMode: enumFromName(LoadMode.values, j['loadMode']),
    primary: listOf(j['primary'], (e) => enumFromName(MuscleGroup.values, e)),
    secondary: listOf(j['secondary'], (e) {
      final m = asJson(e);
      return CatalogSecondary(enumFromName(MuscleGroup.values, m['muscle']), optDouble(m['factor']));
    }),
    increment: toDouble(j['increment']),
    repMin: optInt(j['repMin']),
    repMax: optInt(j['repMax']),
    restSeconds: optInt(j['restSeconds']),
  );

  Exercise makeExercise() {
    final config = ProgressionConfig(increment: increment);
    if (measurement == MeasurementType.duration) {
      if (repMin != null) config.secondsMin = repMin!;
      if (repMax != null) config.secondsMax = repMax!;
    } else {
      if (repMin != null) config.repMin = repMin!;
      if (repMax != null) config.repMax = repMax!;
    }
    return Exercise(
      id: uuid,
      catalogId: catalogId,
      name: name,
      measurement: measurement,
      equipment: equipment,
      loadMode: loadMode,
      primaryMuscles: List.of(primary),
      secondaryMuscles: [for (final s in secondary) MuscleInvolvement(s.muscle, s.factor)],
      defaultIncrement: increment,
      progression: config.sanitized(),
      defaultRestSeconds: restSeconds,
      isCustom: false,
    );
  }
}

class ExerciseCatalog {
  final int version;
  final List<CatalogEntry> exercises;
  const ExerciseCatalog(this.version, this.exercises);

  factory ExerciseCatalog.fromJson(Json j) =>
      ExerciseCatalog(toInt(j['version']), listOf(j['exercises'], (e) => CatalogEntry.fromJson(asJson(e))));

  /// The catalog shipped with the app.
  static ExerciseCatalog bundled() => ExerciseCatalog.fromJson(asJson(jsonDecode(bundledCatalogJson)));
}

class PresetItem {
  final String catalogId;
  final int sets;
  final int repMin;
  final int repMax;
  final int? restSeconds;
  const PresetItem(this.catalogId, this.sets, this.repMin, this.repMax, [this.restSeconds]);
}

/// Editable starting routines. Nothing is created unless the user picks one.
class RoutinePreset {
  final String id;
  final String name;
  final String notes;
  final List<PresetItem> exercises;
  const RoutinePreset(this.id, this.name, this.notes, this.exercises);

  static const List<RoutinePreset> all = [
    RoutinePreset('full-body-a', 'Full body A', 'Plantilla inicial editable.', [
      PresetItem('barbell-back-squat', 3, 6, 10, 150),
      PresetItem('barbell-bench-press', 3, 6, 10, 150),
      PresetItem('barbell-row', 3, 8, 12, 120),
      PresetItem('dumbbell-shoulder-press', 2, 8, 12),
      PresetItem('romanian-deadlift', 2, 8, 12, 120),
      PresetItem('plank', 2, 30, 60, 60),
    ]),
    RoutinePreset('upper', 'Torso', 'Plantilla inicial editable (torso/pierna).', [
      PresetItem('barbell-bench-press', 3, 6, 10, 150),
      PresetItem('lat-pulldown', 3, 8, 12),
      PresetItem('incline-dumbbell-press', 3, 8, 12),
      PresetItem('seated-cable-row', 3, 8, 12),
      PresetItem('dumbbell-lateral-raise', 3, 12, 15, 60),
      PresetItem('cable-triceps-pushdown', 2, 10, 15, 60),
      PresetItem('dumbbell-curl', 2, 10, 15, 60),
    ]),
    RoutinePreset('lower', 'Pierna', 'Plantilla inicial editable (torso/pierna).', [
      PresetItem('barbell-back-squat', 3, 6, 10, 150),
      PresetItem('romanian-deadlift', 3, 8, 12, 120),
      PresetItem('leg-press', 3, 10, 15),
      PresetItem('lying-leg-curl', 3, 10, 15, 60),
      PresetItem('standing-calf-raise', 3, 10, 15, 60),
    ]),
    RoutinePreset('push', 'Empuje', 'Plantilla inicial editable (push/pull/legs).', [
      PresetItem('barbell-bench-press', 3, 6, 10, 150),
      PresetItem('overhead-press', 3, 6, 10, 150),
      PresetItem('incline-dumbbell-press', 3, 8, 12),
      PresetItem('dumbbell-lateral-raise', 3, 12, 15, 60),
      PresetItem('cable-triceps-pushdown', 3, 10, 15, 60),
    ]),
    RoutinePreset('pull', 'Tirón', 'Plantilla inicial editable (push/pull/legs).', [
      PresetItem('pull-up', 3, 5, 10, 150),
      PresetItem('barbell-row', 3, 8, 12, 120),
      PresetItem('seated-cable-row', 3, 8, 12),
      PresetItem('face-pull', 3, 12, 15, 60),
      PresetItem('dumbbell-curl', 3, 10, 15, 60),
    ]),
    RoutinePreset('legs', 'Piernas', 'Plantilla inicial editable (push/pull/legs).', [
      PresetItem('barbell-back-squat', 3, 6, 10, 150),
      PresetItem('romanian-deadlift', 3, 8, 12, 120),
      PresetItem('bulgarian-split-squat', 3, 8, 12),
      PresetItem('leg-extension', 3, 10, 15, 60),
      PresetItem('standing-calf-raise', 3, 10, 15, 60),
    ]),
  ];
}
