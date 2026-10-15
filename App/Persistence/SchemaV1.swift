import Foundation
import SwiftData

// SwiftData schema, version 1. Records are flat (foreign keys as UUIDs, no SwiftData relationships)
// and nested value types are stored as JSON `Data`. This keeps the mapping to the GymStore records
// 1:1 and lossless, and keeps migrations explicit: a new `SchemaV2` + a `MigrationStage` here.
//
// UNVERIFIED: written without Xcode (see docs/ENVIRONMENT.md). The same contract is verified on
// Linux through `JSONGymRepository` and the GymStore tests.

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            ExerciseModel.self,
            RoutineModel.self,
            RoutineExerciseModel.self,
            ScheduleEntryModel.self,
            SessionModel.self,
            ExerciseLogModel.self,
            SetLogModel.self,
            DecisionModel.self,
            ComparabilityLinkModel.self,
            GoalModel.self,
            SettingsModel.self,
        ]
    }

    @Model
    final class ExerciseModel {
        @Attribute(.unique) var id: UUID
        var catalogId: String?
        var name: String
        var isCustom: Bool
        var isArchived: Bool
        /// Full `Exercise` as JSON (measurement, muscles, progression…).
        var payload: Data

        init(id: UUID, catalogId: String?, name: String, isCustom: Bool, isArchived: Bool, payload: Data) {
            self.id = id
            self.catalogId = catalogId
            self.name = name
            self.isCustom = isCustom
            self.isArchived = isArchived
            self.payload = payload
        }
    }

    @Model
    final class RoutineModel {
        @Attribute(.unique) var id: UUID
        var name: String
        var sortOrder: Int
        var notes: String
        var isArchived: Bool
        var createdAt: Date

        init(id: UUID, name: String, sortOrder: Int, notes: String, isArchived: Bool, createdAt: Date) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
            self.notes = notes
            self.isArchived = isArchived
            self.createdAt = createdAt
        }
    }

    @Model
    final class RoutineExerciseModel {
        @Attribute(.unique) var id: UUID
        var routineId: UUID
        var exerciseId: UUID
        var sortOrder: Int
        var payload: Data

        init(id: UUID, routineId: UUID, exerciseId: UUID, sortOrder: Int, payload: Data) {
            self.id = id
            self.routineId = routineId
            self.exerciseId = exerciseId
            self.sortOrder = sortOrder
            self.payload = payload
        }
    }

    @Model
    final class ScheduleEntryModel {
        @Attribute(.unique) var id: UUID
        var validFrom: Date
        var payload: Data

        init(id: UUID, validFrom: Date, payload: Data) {
            self.id = id
            self.validFrom = validFrom
            self.payload = payload
        }
    }

    @Model
    final class SessionModel {
        @Attribute(.unique) var id: UUID
        var routineId: UUID?
        var startedAt: Date
        var statusRaw: String
        var payload: Data

        init(id: UUID, routineId: UUID?, startedAt: Date, statusRaw: String, payload: Data) {
            self.id = id
            self.routineId = routineId
            self.startedAt = startedAt
            self.statusRaw = statusRaw
            self.payload = payload
        }
    }

    @Model
    final class ExerciseLogModel {
        @Attribute(.unique) var id: UUID
        var sessionId: UUID
        var exerciseId: UUID
        var plannedOrder: Int
        /// Full `ExerciseLog` (snapshots, context, frozen recommendation) as JSON.
        var payload: Data

        init(id: UUID, sessionId: UUID, exerciseId: UUID, plannedOrder: Int, payload: Data) {
            self.id = id
            self.sessionId = sessionId
            self.exerciseId = exerciseId
            self.plannedOrder = plannedOrder
            self.payload = payload
        }
    }

    @Model
    final class SetLogModel {
        @Attribute(.unique) var id: UUID
        var exerciseLogId: UUID
        var index: Int
        var payload: Data

        init(id: UUID, exerciseLogId: UUID, index: Int, payload: Data) {
            self.id = id
            self.exerciseLogId = exerciseLogId
            self.index = index
            self.payload = payload
        }
    }

    @Model
    final class DecisionModel {
        @Attribute(.unique) var exerciseLogId: UUID
        var id: UUID
        var decidedAt: Date
        var payload: Data

        init(exerciseLogId: UUID, id: UUID, decidedAt: Date, payload: Data) {
            self.exerciseLogId = exerciseLogId
            self.id = id
            self.decidedAt = decidedAt
            self.payload = payload
        }
    }

    @Model
    final class ComparabilityLinkModel {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var payload: Data

        init(id: UUID, createdAt: Date, payload: Data) {
            self.id = id
            self.createdAt = createdAt
            self.payload = payload
        }
    }

    @Model
    final class GoalModel {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var payload: Data

        init(id: UUID, createdAt: Date, payload: Data) {
            self.id = id
            self.createdAt = createdAt
            self.payload = payload
        }
    }

    @Model
    final class SettingsModel {
        @Attribute(.unique) var key: String
        var payload: Data

        init(key: String, payload: Data) {
            self.key = key
            self.payload = payload
        }
    }
}

/// Migration plan from day one. Add `SchemaV2` to `schemas` and a stage to `stages` when the model
/// changes; never edit `SchemaV1` in place after release.
enum GymMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias ExerciseModel = SchemaV1.ExerciseModel
typealias RoutineModel = SchemaV1.RoutineModel
typealias RoutineExerciseModel = SchemaV1.RoutineExerciseModel
typealias ScheduleEntryModel = SchemaV1.ScheduleEntryModel
typealias SessionModel = SchemaV1.SessionModel
typealias ExerciseLogModel = SchemaV1.ExerciseLogModel
typealias SetLogModel = SchemaV1.SetLogModel
typealias DecisionModel = SchemaV1.DecisionModel
typealias ComparabilityLinkModel = SchemaV1.ComparabilityLinkModel
typealias GoalModel = SchemaV1.GoalModel
typealias SettingsModel = SchemaV1.SettingsModel
