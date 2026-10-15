import Foundation
import GymCore
import GymStore
import Observation
import SwiftData

/// Composition root. Owns the repository and the services; views read data through it and call
/// `perform` for every mutation (which saves immediately and bumps `revision` to refresh views).
@MainActor
@Observable
final class AppModel {
    let repository: any GymRepository
    let workout: WorkoutService
    let routines: RoutineService
    let catalog: ExerciseCatalogService
    let history: HistoryService
    let exporter: ExportService
    let restTimer: RestTimerService

    /// Built on access so days and weeks always use the device's *current* time zone (8.6).
    var consistency: ConsistencyService { ConsistencyService(repository: repository, timeZone: .current) }
    var stats: StatsService { StatsService(repository: repository, timeZone: .current) }

    /// Navigation path of the "Entrenar" tab (exercise screens). Superset hops replace the top
    /// screen instead of stacking A → B → A → B…
    var workoutPath: [UUID] = []

    /// Incremented after each successful mutation; views read it to re-render.
    private(set) var revision = 0
    var errorMessage: String?
    /// The persistent store could not be opened: the app shows a blocking screen and accepts no
    /// workouts (anything logged would be lost on relaunch).
    private(set) var storeError: String?
    var selectedTab: AppTab = .home

    init(repository: any GymRepository) {
        self.repository = repository
        self.workout = WorkoutService(repository: repository)
        self.routines = RoutineService(repository: repository)
        self.catalog = ExerciseCatalogService(repository: repository)
        self.history = HistoryService(repository: repository)
        self.exporter = ExportService(repository: repository)
        self.restTimer = RestTimerService()
    }

    /// Production model on the persistent SwiftData store.
    static func live() -> AppModel {
        do {
            let container = try SwiftDataGymRepository.makeContainer()
            let model = AppModel(repository: SwiftDataGymRepository(container: container))
            model.seedCatalogIfNeeded()
            return model
        } catch {
            // Never pretend to work on a temporary store: block the UI and explain.
            let fallback = try! SwiftDataGymRepository.makeContainer(inMemory: true)
            let model = AppModel(repository: SwiftDataGymRepository(container: fallback))
            model.storeError = "No se pudo abrir la base de datos de la app. Tus datos no se modificaron. Cerrá la app y volvé a abrirla; si el problema sigue, no registres entrenamientos hasta resolverlo.\n\nDetalle: \(error.localizedDescription)"
            return model
        }
    }

    var settings: UserSettings { repository.settings() }
    var loadFormatter: LoadFormatter { LoadFormatter(unit: settings.weightUnit) }

    /// The clock is read only here, at the UI edge; services and the engine receive it injected.
    /// The workout service follows the current time zone too (travel, DST).
    func now() -> Date {
        if workout.timeZone != .current { workout.timeZone = .current }
        return Date()
    }

    /// Runs a mutation, surfaces errors in Spanish, refreshes views.
    @discardableResult
    func perform<T>(_ action: () throws -> T) -> T? {
        do {
            let result = try action()
            revision += 1
            return result
        } catch let error as GymStoreError {
            errorMessage = Self.message(for: error)
            revision += 1
            return nil
        } catch {
            errorMessage = error.localizedDescription
            revision += 1
            return nil
        }
    }

    func seedCatalogIfNeeded() {
        guard let catalog = try? ExerciseCatalog.bundled() else { return }
        perform { try self.catalog.seed(catalog) }
    }

    static func message(for error: GymStoreError) -> String {
        switch error {
        case let .notFound(what): what.contains(" ") ? what : "No se encontró el elemento."
        case .sessionAlreadyOpen: "Ya hay un entrenamiento en curso. Terminalo o descartalo antes de empezar otro."
        case .sessionNotOpen: "El entrenamiento ya no está en curso."
        case .hasHistory: "Tiene historial: no se puede borrar, pero podés archivarlo."
        case .hasCompletedSets: "Este ejercicio ya tiene series completadas en la sesión."
        case .missingValues: "Completá peso y repeticiones antes de marcar la serie."
        case let .invalidValue(message): message
        case let .unsupportedSchemaVersion(v): "La copia es de una versión más nueva de la app (esquema \(v))."
        case let .invalidImport(message): message
        case let .storage(message): "Error al guardar: \(message)"
        }
    }
}

enum AppTab: Hashable {
    case home
    case routines
    case workout
    case progress
    case profile
}
