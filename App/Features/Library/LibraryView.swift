import GymCore
import GymStore
import SwiftUI

/// Exercise library management: browse, create custom exercises, edit criteria, archive.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var muscle: MuscleGroup?
    @State private var showCustom = false
    @State private var showArchived = false

    var body: some View {
        let _ = model.revision
        let all = model.repository.exercises()
        let matches: (Exercise) -> Bool = { exercise in
            (query.isEmpty || exercise.name.localizedStandardContains(query))
                && (muscle == nil || exercise.primaryMuscles.contains(muscle!) || exercise.secondaryMuscles.contains { $0.muscle == muscle! })
        }
        let active = all.filter { !$0.isArchived && matches($0) }
        let archived = all.filter { $0.isArchived && matches($0) }

        List {
            Section {
                Picker("Músculo", selection: $muscle) {
                    Text("Todos").tag(MuscleGroup?.none)
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
            Section("\(active.count) ejercicios") {
                ForEach(active) { exercise in
                    NavigationLink { ExerciseDetailView(exerciseId: exercise.id) } label: { ExerciseRow(exercise: exercise) }
                }
            }
            if !archived.isEmpty {
                Section {
                    DisclosureGroup("Archivados (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { exercise in
                            NavigationLink { ExerciseDetailView(exerciseId: exercise.id) } label: { ExerciseRow(exercise: exercise) }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar ejercicio")
        .navigationTitle("Biblioteca")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCustom = true } label: { Label("Nuevo ejercicio", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showCustom) {
            NavigationStack { CustomExerciseForm { _ in showCustom = false } }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(exercise.name)
                if exercise.isCustom { Badge(text: "Propio") }
            }
            Text("\(exercise.equipment.label) · \(exercise.primaryMuscles.map(\.label).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Exercise detail: muscles, default progression criteria (section 2.B), archive / delete.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let exerciseId: UUID

    @State private var name = ""
    @State private var config = ProgressionConfig()
    @State private var hasRIR = true
    @State private var rir = 2
    @State private var incrementText = ""
    @State private var initialText = ""
    @State private var availableText = ""
    @State private var restSeconds = 120
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        let _ = model.revision
        if let exercise = model.repository.exercise(id: exerciseId) {
            form(exercise)
        } else {
            ContentUnavailableView("Ejercicio eliminado", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func form(_ exercise: Exercise) -> some View {
        let unit = model.settings.weightUnit.rawValue
        let hasHistory = model.repository.hasHistory(exerciseId: exerciseId)
        Form {
            Section {
                if exercise.isCustom {
                    TextField("Nombre", text: $name)
                } else {
                    LabeledContent("Nombre", value: exercise.name)
                }
                LabeledContent("Medición", value: exercise.measurement.label)
                LabeledContent("Equipamiento", value: exercise.equipment.label)
                LabeledContent("Carga", value: exercise.loadMode == .perSide ? "Por lado / por mano" : "Total")
                LabeledContent("Principales", value: exercise.primaryMuscles.map(\.label).joined(separator: ", "))
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secundarios", value: exercise.secondaryMuscles.map(\.muscle.label).joined(separator: ", "))
                }
            }

            Section {
                Stepper("Series: \(config.targetSets)", value: $config.targetSets, in: 1...10)
                if exercise.measurement == .duration {
                    Stepper("Mínimo: \(config.secondsMin) s", value: $config.secondsMin, in: 5...600, step: 5)
                    Stepper("Máximo: \(config.secondsMax) s", value: $config.secondsMax, in: config.secondsMin...900, step: 5)
                } else {
                    Stepper("Repeticiones mínimas: \(config.repMin)", value: $config.repMin, in: 1...50)
                    Stepper("Repeticiones máximas: \(config.repMax)", value: $config.repMax, in: config.repMin...60)
                }
                Toggle("RIR objetivo", isOn: $hasRIR)
                if hasRIR { Stepper("RIR \(rir)", value: $rir, in: 0...5) }
                LabeledContent("Incremento (\(unit))") {
                    TextField("2,5", text: $incrementText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Peso inicial (\(unit))") {
                    TextField("Opcional", text: $initialText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                TextField("Pesos disponibles (ej.: 20; 22,5; 25)", text: $availableText)
                Stepper("Sesiones al tope antes de subir: \(config.requiredConsecutiveSessions)", value: $config.requiredConsecutiveSessions, in: 1...5)
                Stepper("Reevaluar tras \(config.reassessAfterDays) días", value: $config.reassessAfterDays, in: 7...90, step: 7)
                Stepper("Descanso: \(restSeconds) s", value: $restSeconds, in: 15...600, step: 15)
                Button("Guardar criterios") { save(exercise) }
            } header: {
                Text("Criterios de progresión predeterminados")
            } footer: {
                Text("Se aplican en rutinas sin criterios propios. Cambiarlos no modifica sesiones pasadas.")
            }

            Section {
                NavigationLink("Historial y próxima recomendación") { ExerciseHistoryView(exerciseId: exerciseId) }
                Button(exercise.isArchived ? "Restaurar" : "Archivar") {
                    model.perform { try model.catalog.setArchived(exerciseId: exerciseId, !exercise.isArchived) }
                }
                if !hasHistory {
                    Button("Eliminar", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                if hasHistory {
                    Text("Tiene historial: se puede archivar (deja de aparecer en la biblioteca) pero no eliminar.")
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load(exercise) }
        .confirmationDialog("¿Eliminar \"\(exercise.name)\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if model.perform({ try model.catalog.deleteExercise(id: exerciseId) }) != nil { dismiss() }
            }
        } message: {
            Text("No tiene historial. También se quita de las rutinas donde aparece.")
        }
    }

    private func load(_ exercise: Exercise) {
        guard !loaded else { return }
        loaded = true
        let fmt = model.loadFormatter
        name = exercise.name
        config = exercise.progression
        hasRIR = config.targetRIR != nil
        rir = config.targetRIR ?? 2
        incrementText = fmt.editable(config.increment)
        initialText = fmt.editable(config.initialWeight)
        availableText = (config.availableWeights ?? []).map { fmt.editable($0) }.joined(separator: "; ")
        restSeconds = exercise.defaultRestSeconds ?? model.settings.defaultRestSeconds
    }

    private func save(_ exercise: Exercise) {
        let fmt = model.loadFormatter
        var updated = exercise
        if exercise.isCustom { updated.name = name }
        var c = config
        c.targetRIR = hasRIR ? rir : nil
        if let inc = fmt.parse(incrementText), inc > 0 { c.increment = inc }
        c.initialWeight = initialText.isEmpty ? nil : fmt.parse(initialText)
        let weights = availableText.split(separator: ";").compactMap { fmt.parse(String($0)) }
        c.availableWeights = weights.isEmpty ? nil : weights
        updated.progression = c
        updated.defaultIncrement = c.increment
        updated.availableWeights = c.availableWeights
        updated.defaultRestSeconds = restSeconds
        model.perform { try model.catalog.updateExercise(updated) }
    }
}
