/// Enumerations mirroring GymCore/Models/Enums.swift. `name` is the Swift raw value.
library;

T enumFromName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown ${T.toString()}: $name');
}

enum MeasurementType { weightReps, bodyweightReps, duration }

enum LoadMode { total, perSide }

enum Equipment { barbell, dumbbell, machine, cable, smithMachine, kettlebell, bodyweight, band, ezBar, other }

/// Swift sorts MuscleGroup by raw value (`Comparable`).
enum MuscleGroup {
  chest,
  upperBack,
  lats,
  traps,
  frontDelts,
  sideDelts,
  rearDelts,
  biceps,
  triceps,
  forearms,
  quads,
  hamstrings,
  glutes,
  calves,
  adductors,
  abductors,
  abs,
  obliques,
  lowerBack;

  static int compareByRawValue(MuscleGroup a, MuscleGroup b) => a.name.compareTo(b.name);
}

enum SetKind {
  warmup,
  working,
  dropSet;

  /// Counts toward volume and effective-set statistics.
  bool get countsAsEffectiveWork => this != SetKind.warmup;

  /// Feeds the progression engine (only straight working sets are compared).
  bool get feedsProgression => this == SetKind.working;
}

enum SetStatus { pending, completed }

enum SessionStatus { active, paused, completed, discarded }
