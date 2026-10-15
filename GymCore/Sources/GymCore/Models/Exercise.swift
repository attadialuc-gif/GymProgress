import Foundation

/// A secondary muscle with its participation factor (0...1). `nil` factor = use the global
/// indirect-set factor from settings.
public struct MuscleInvolvement: Codable, Sendable, Hashable {
    public var muscle: MuscleGroup
    public var factor: Double?

    public init(muscle: MuscleGroup, factor: Double? = nil) {
        self.muscle = muscle
        self.factor = factor
    }
}

/// Catalog definition of an exercise. History never depends on it after the fact: logs keep a
/// snapshot of the relevant fields.
public struct Exercise: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Stable id inside the bundled catalog JSON (`nil` for user-created exercises).
    public var catalogId: String?
    public var name: String
    public var measurement: MeasurementType
    public var equipment: Equipment
    public var loadMode: LoadMode
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleInvolvement]
    public var defaultIncrement: Double
    public var availableWeights: [Double]?
    public var progression: ProgressionConfig
    public var defaultRestSeconds: Int?
    public var notes: String
    public var isCustom: Bool
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        catalogId: String? = nil,
        name: String,
        measurement: MeasurementType = .weightReps,
        equipment: Equipment = .barbell,
        loadMode: LoadMode = .total,
        primaryMuscles: [MuscleGroup] = [],
        secondaryMuscles: [MuscleInvolvement] = [],
        defaultIncrement: Double = 2.5,
        availableWeights: [Double]? = nil,
        progression: ProgressionConfig = .default,
        defaultRestSeconds: Int? = nil,
        notes: String = "",
        isCustom: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.catalogId = catalogId
        self.name = name
        self.measurement = measurement
        self.equipment = equipment
        self.loadMode = loadMode
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.defaultIncrement = defaultIncrement
        self.availableWeights = availableWeights
        self.progression = progression
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
        self.isCustom = isCustom
        self.isArchived = isArchived
    }

    /// Default comparability context (no variant, no specific machine).
    public var defaultContext: ComparabilityContext {
        ComparabilityContext(exerciseId: id, loadMode: loadMode)
    }
}

/// Fields of an exercise frozen inside each log so that later catalog edits never alter history.
public struct ExerciseSnapshot: Codable, Sendable, Hashable {
    public var exerciseId: UUID
    public var name: String
    public var measurement: MeasurementType
    public var equipment: Equipment
    public var loadMode: LoadMode
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleInvolvement]

    public init(
        exerciseId: UUID,
        name: String,
        measurement: MeasurementType,
        equipment: Equipment,
        loadMode: LoadMode,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleInvolvement]
    ) {
        self.exerciseId = exerciseId
        self.name = name
        self.measurement = measurement
        self.equipment = equipment
        self.loadMode = loadMode
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
    }

    public init(_ exercise: Exercise) {
        self.init(
            exerciseId: exercise.id,
            name: exercise.name,
            measurement: exercise.measurement,
            equipment: exercise.equipment,
            loadMode: exercise.loadMode,
            primaryMuscles: exercise.primaryMuscles,
            secondaryMuscles: exercise.secondaryMuscles
        )
    }
}
