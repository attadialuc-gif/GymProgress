import Foundation
import GymCore

/// Bundled, versioned exercise library (`Resources/exercises.json`). Every entry has a fixed UUID
/// and a stable `catalogId`, so seeding is idempotent across devices and exports never duplicate.
public struct ExerciseCatalog: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public struct Secondary: Codable, Sendable, Hashable {
            public var muscle: MuscleGroup
            public var factor: Double?
        }

        public var uuid: UUID
        public var catalogId: String
        public var name: String
        public var measurement: MeasurementType
        public var equipment: Equipment
        public var loadMode: LoadMode
        public var primary: [MuscleGroup]
        public var secondary: [Secondary]
        public var increment: Double
        public var repMin: Int?
        public var repMax: Int?
        public var restSeconds: Int?

        public func makeExercise() -> Exercise {
            var config = ProgressionConfig(increment: increment)
            if measurement == .duration {
                if let repMin { config.secondsMin = repMin }
                if let repMax { config.secondsMax = repMax }
            } else {
                if let repMin { config.repMin = repMin }
                if let repMax { config.repMax = repMax }
            }
            return Exercise(
                id: uuid,
                catalogId: catalogId,
                name: name,
                measurement: measurement,
                equipment: equipment,
                loadMode: loadMode,
                primaryMuscles: primary,
                secondaryMuscles: secondary.map { MuscleInvolvement(muscle: $0.muscle, factor: $0.factor) },
                defaultIncrement: increment,
                progression: config.sanitized(),
                defaultRestSeconds: restSeconds,
                isCustom: false
            )
        }
    }

    public var version: Int
    public var exercises: [Entry]

    /// The catalog shipped with the package.
    public static func bundled() throws -> ExerciseCatalog {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw GymStoreError.notFound("exercises.json")
        }
        return try JSONDecoder().decode(ExerciseCatalog.self, from: Data(contentsOf: url))
    }
}

/// Editable starting routines. Nothing is created unless the user picks one.
public struct RoutinePreset: Codable, Sendable, Hashable, Identifiable {
    public struct Item: Codable, Sendable, Hashable {
        public var catalogId: String
        public var sets: Int
        public var repMin: Int
        public var repMax: Int
        public var restSeconds: Int?
    }

    public var id: String
    public var name: String
    public var notes: String
    public var exercises: [Item]

    static func item(_ id: String, _ sets: Int, _ min: Int, _ max: Int, rest: Int? = nil) -> Item {
        Item(catalogId: id, sets: sets, repMin: min, repMax: max, restSeconds: rest)
    }

    public static let all: [RoutinePreset] = [
        RoutinePreset(id: "full-body-a", name: "Full body A", notes: "Plantilla inicial editable.", exercises: [
            item("barbell-back-squat", 3, 6, 10, rest: 150),
            item("barbell-bench-press", 3, 6, 10, rest: 150),
            item("barbell-row", 3, 8, 12, rest: 120),
            item("dumbbell-shoulder-press", 2, 8, 12),
            item("romanian-deadlift", 2, 8, 12, rest: 120),
            item("plank", 2, 30, 60, rest: 60),
        ]),
        RoutinePreset(id: "upper", name: "Torso", notes: "Plantilla inicial editable (torso/pierna).", exercises: [
            item("barbell-bench-press", 3, 6, 10, rest: 150),
            item("lat-pulldown", 3, 8, 12),
            item("incline-dumbbell-press", 3, 8, 12),
            item("seated-cable-row", 3, 8, 12),
            item("dumbbell-lateral-raise", 3, 12, 15, rest: 60),
            item("cable-triceps-pushdown", 2, 10, 15, rest: 60),
            item("dumbbell-curl", 2, 10, 15, rest: 60),
        ]),
        RoutinePreset(id: "lower", name: "Pierna", notes: "Plantilla inicial editable (torso/pierna).", exercises: [
            item("barbell-back-squat", 3, 6, 10, rest: 150),
            item("romanian-deadlift", 3, 8, 12, rest: 120),
            item("leg-press", 3, 10, 15),
            item("lying-leg-curl", 3, 10, 15, rest: 60),
            item("standing-calf-raise", 3, 10, 15, rest: 60),
        ]),
        RoutinePreset(id: "push", name: "Empuje", notes: "Plantilla inicial editable (push/pull/legs).", exercises: [
            item("barbell-bench-press", 3, 6, 10, rest: 150),
            item("overhead-press", 3, 6, 10, rest: 150),
            item("incline-dumbbell-press", 3, 8, 12),
            item("dumbbell-lateral-raise", 3, 12, 15, rest: 60),
            item("cable-triceps-pushdown", 3, 10, 15, rest: 60),
        ]),
        RoutinePreset(id: "pull", name: "Tirón", notes: "Plantilla inicial editable (push/pull/legs).", exercises: [
            item("pull-up", 3, 5, 10, rest: 150),
            item("barbell-row", 3, 8, 12, rest: 120),
            item("seated-cable-row", 3, 8, 12),
            item("face-pull", 3, 12, 15, rest: 60),
            item("dumbbell-curl", 3, 10, 15, rest: 60),
        ]),
        RoutinePreset(id: "legs", name: "Piernas", notes: "Plantilla inicial editable (push/pull/legs).", exercises: [
            item("barbell-back-squat", 3, 6, 10, rest: 150),
            item("romanian-deadlift", 3, 8, 12, rest: 120),
            item("bulgarian-split-squat", 3, 8, 12),
            item("leg-extension", 3, 10, 15, rest: 60),
            item("standing-calf-raise", 3, 10, 15, rest: 60),
        ]),
    ]
}
