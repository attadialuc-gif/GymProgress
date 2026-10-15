import GymCore
import GymStore
import SwiftUI

/// Library search (bundled catalog + custom exercises).
struct ExercisePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @State private var muscle: MuscleGroup?
    @State private var showCustom = false

    var body: some View {
        let _ = model.revision
        let all = model.repository.exercises().filter { !$0.isArchived }
        let filtered = all.filter { exercise in
            (query.isEmpty || exercise.name.localizedStandardContains(query))
                && (muscle == nil || exercise.primaryMuscles.contains(muscle!) || exercise.secondaryMuscles.contains { $0.muscle == muscle! })
        }

        List {
            Section {
                Picker("Músculo", selection: $muscle) {
                    Text("Todos").tag(MuscleGroup?.none)
                    ForEach(MuscleGroup.allCases, id: \.self) { m in
                        Text(m.label).tag(Optional(m))
                    }
                }
            }
            Section {
                Button { showCustom = true } label: { Label("Crear ejercicio personalizado", systemImage: "plus") }
            }
            Section("\(filtered.count) ejercicios") {
                ForEach(filtered) { exercise in
                    Button { onPick(exercise) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(exercise.name).foregroundStyle(.primary)
                                if exercise.isCustom { Badge(text: "Propio") }
                            }
                            Text("\(exercise.equipment.label) · \(exercise.primaryMuscles.map(\.label).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar ejercicio")
        .navigationTitle("Biblioteca")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
        }
        .sheet(isPresented: $showCustom) {
            NavigationStack {
                CustomExerciseForm { created in
                    showCustom = false
                    onPick(created)
                }
            }
        }
    }
}

struct CustomExerciseForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Exercise) -> Void

    @State private var name = ""
    @State private var measurement: MeasurementType = .weightReps
    @State private var equipment: Equipment = .machine
    @State private var perSide = false
    @State private var primary: Set<MuscleGroup> = []
    @State private var secondary: Set<MuscleGroup> = []
    @State private var incrementText = "2,5"

    var body: some View {
        Form {
            Section {
                TextField("Nombre", text: $name)
                Picker("Medición", selection: $measurement) {
                    ForEach(MeasurementType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Equipamiento", selection: $equipment) {
                    ForEach(Equipment.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Peso por lado / por mano", isOn: $perSide)
                LabeledContent("Incremento (\(model.settings.weightUnit.rawValue))") {
                    TextField("2,5", text: $incrementText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Músculos principales") {
                muscleToggles($primary)
            }
            Section("Músculos secundarios") {
                muscleToggles($secondary)
            }
        }
        .navigationTitle("Nuevo ejercicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Crear") {
                    let increment = model.loadFormatter.parse(incrementText) ?? 2.5
                    if let created = model.perform({
                        try model.catalog.createCustomExercise(
                            name: name,
                            measurement: measurement,
                            equipment: equipment,
                            loadMode: perSide ? .perSide : .total,
                            primaryMuscles: MuscleGroup.allCases.filter { primary.contains($0) },
                            secondaryMuscles: MuscleGroup.allCases.filter { secondary.contains($0) && !primary.contains($0) }.map { MuscleInvolvement(muscle: $0) },
                            increment: increment
                        )
                    }) {
                        onCreated(created)
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func muscleToggles(_ selection: Binding<Set<MuscleGroup>>) -> some View {
        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
            Toggle(muscle.label, isOn: Binding(
                get: { selection.wrappedValue.contains(muscle) },
                set: { on in
                    if on { selection.wrappedValue.insert(muscle) } else { selection.wrappedValue.remove(muscle) }
                }
            ))
        }
    }
}
