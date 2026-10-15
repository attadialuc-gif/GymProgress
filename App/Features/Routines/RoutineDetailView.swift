import GymCore
import GymStore
import SwiftUI

/// Routine editor + recommendation preview + start button.
struct RoutineDetailView: View {
    @Environment(AppModel.self) private var model
    let routineId: UUID

    @State private var showPicker = false
    @State private var editing: RoutineExercise?
    @State private var showRename = false
    @State private var newName = ""

    var body: some View {
        let _ = model.revision
        if let routine = model.repository.routine(id: routineId) {
            content(routine)
        } else {
            ContentUnavailableView("Rutina no encontrada", systemImage: "questionmark")
        }
    }

    @ViewBuilder
    private func content(_ routine: RoutineTemplate) -> some View {
        let items = model.repository.routineExercises(routineId: routineId)
        let previews = Dictionary(uniqueKeysWithValues: model.workout.previewRecommendations(routineId: routineId, now: model.now()).map { ($0.0.id, $0.2) })
        let openSession = model.workout.openSession()

        List {
            Section {
                Button {
                    if model.perform({ try model.workout.startSession(routineId: routineId, now: model.now()) }) != nil {
                        model.selectedTab = .workout
                    }
                } label: {
                    Label("Comenzar entrenamiento", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty || openSession != nil)
                .listRowBackground(Color.clear)
                if openSession != nil {
                    Text("Ya hay un entrenamiento en curso (pestaña Entrenar).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Ejercicios") {
                ForEach(items) { item in
                    if let exercise = model.repository.exercise(id: item.exerciseId) {
                        Button { editing = item } label: {
                            RoutineExerciseRow(item: item, exercise: exercise, config: model.routines.effectiveConfig(for: item) ?? exercise.progression, preview: previews[item.id])
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { model.perform { try model.routines.removeRoutineExercise(id: item.id) } } label: {
                                Label("Quitar", systemImage: "minus.circle")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading) {
                            Button { model.perform { try model.routines.duplicateRoutineExercise(id: item.id) } } label: {
                                Label("Duplicar", systemImage: "plus.square.on.square")
                            }
                            .tint(Theme.accent)
                        }
                    }
                }
                .onMove { from, to in
                    var ids = items.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.perform { try model.routines.moveExercises(routineId: routineId, orderedIds: ids) }
                }
                Button { showPicker = true } label: { Label("Agregar ejercicio", systemImage: "plus") }
            }

            if !routine.notes.isEmpty {
                Section("Notas") { Text(routine.notes) }
            }
        }
        .navigationTitle(routine.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = routine.name; showRename = true } label: { Label("Renombrar", systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ExercisePickerView { exercise in
                    model.perform { try model.routines.addExercise(routineId: routineId, exerciseId: exercise.id) }
                    showPicker = false
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack { RoutineExerciseEditor(item: item) }
        }
        .alert("Renombrar rutina", isPresented: $showRename) {
            TextField("Nombre", text: $newName)
            Button("Guardar") {
                var updated = routine
                updated.name = newName
                model.perform { try model.routines.updateRoutine(updated) }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

private struct RoutineExerciseRow: View {
    @Environment(AppModel.self) private var model
    let item: RoutineExercise
    let exercise: Exercise
    let config: ProgressionConfig
    let preview: Recommendation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(exercise.name).font(.headline)
                if let group = item.supersetGroup { Badge(text: "Superserie \(group)") }
            }
            Text(targetText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let preview {
                // Recommendation summary also appears in the routine preview (section 2.A).
                HStack(spacing: 6) {
                    Image(systemName: preview.actionSymbol).foregroundStyle(Theme.accent)
                    Text(summary(preview)).font(.footnote)
                    if preview.confidence == .conditional { Badge(text: "Condicionada", color: Theme.caution) }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var targetText: String {
        let rir = config.targetRIR.map { " · RIR \($0)" } ?? ""
        if exercise.measurement == .duration {
            return "\(config.targetSets) × \(config.secondsMin)–\(config.secondsMax) s\(rir)"
        }
        return "\(config.targetSets) × \(config.repMin)–\(config.repMax)\(rir)"
    }

    private func summary(_ r: Recommendation) -> String {
        let fmt = model.loadFormatter
        switch r.action {
        case .needsInitialTarget:
            return r.targetWeight == nil ? "Sin datos: configurá un objetivo inicial" : "Inicial: \(fmt.load(r.targetWeight, measurement: r.measurement, loadMode: r.context.loadMode))"
        default:
            return "\(r.actionTitle): \(fmt.load(r.targetWeight, measurement: r.measurement, loadMode: r.context.loadMode)) × \(r.amountsText)"
        }
    }
}
