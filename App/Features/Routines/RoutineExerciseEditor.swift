import GymCore
import GymStore
import SwiftUI

/// Target and progression criteria for one exercise of a routine (section 2.B: editable per
/// exercise — range, sets, RIR, increment, available weights, consecutive sessions, strategy).
struct RoutineExerciseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let item: RoutineExercise
    @State private var config = ProgressionConfig()
    @State private var hasRIR = true
    @State private var rir = 2
    @State private var initialWeightText = ""
    @State private var incrementText = ""
    @State private var availableText = ""
    @State private var restSeconds = 120
    @State private var notes = ""
    @State private var supersetGroup = 0
    @State private var applyToExercise = false
    @State private var loaded = false

    var body: some View {
        let exercise = model.repository.exercise(id: item.exerciseId)
        let isDuration = exercise?.measurement == .duration
        let unit = model.settings.weightUnit.rawValue

        Form {
            Section("Objetivo") {
                Stepper("Series: \(config.targetSets)", value: $config.targetSets, in: 1...10)
                if isDuration {
                    Stepper("Mínimo: \(config.secondsMin) s", value: $config.secondsMin, in: 5...600, step: 5)
                    Stepper("Máximo: \(config.secondsMax) s", value: $config.secondsMax, in: config.secondsMin...900, step: 5)
                    Stepper("Paso: \(config.secondsIncrement) s", value: $config.secondsIncrement, in: 1...60)
                } else {
                    Stepper("Repeticiones mínimas: \(config.repMin)", value: $config.repMin, in: 1...50)
                    Stepper("Repeticiones máximas: \(config.repMax)", value: $config.repMax, in: config.repMin...60)
                }
                Toggle("RIR objetivo", isOn: $hasRIR)
                if hasRIR {
                    Stepper("RIR \(rir) (repeticiones en reserva)", value: $rir, in: 0...5)
                }
            }

            Section {
                LabeledContent("Peso inicial (\(unit))") {
                    TextField("Opcional", text: $initialWeightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Sin historial")
            } footer: {
                Text("Se usa solo cuando todavía no hay sesiones comparables. La app nunca inventa un peso.")
            }

            Section {
                LabeledContent("Incremento (\(unit))") {
                    TextField("2,5", text: $incrementText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Pesos disponibles (ej.: 20; 22,5; 25)", text: $availableText)
                    .keyboardType(.numbersAndPunctuation)
                Stepper("Sesiones al tope antes de subir: \(config.requiredConsecutiveSessions)", value: $config.requiredConsecutiveSessions, in: 1...5)
                Stepper("Reevaluar tras \(config.reassessAfterDays) días sin entrenarlo", value: $config.reassessAfterDays, in: 7...90, step: 7)
                Picker("Estrategia", selection: $config.strategy) {
                    Text("Doble progresión").tag(ProgressionStrategyKind.doubleProgression)
                }
            } header: {
                Text("Progresión")
            } footer: {
                Text("Con pesos disponibles (mancuernas, pila de la máquina) la recomendación usa el siguiente peso real de la lista. Separá los valores con punto y coma.")
            }

            Section("Sesión") {
                Stepper("Descanso: \(restSeconds) s", value: $restSeconds, in: 15...600, step: 15)
                Stepper(supersetGroup == 0 ? "Sin superserie" : "Superserie \(supersetGroup)", value: $supersetGroup, in: 0...9)
                TextField("Notas / técnica", text: $notes, axis: .vertical)
            }

            Section {
                Toggle("Usar también como predeterminado del ejercicio", isOn: $applyToExercise)
            } footer: {
                Text("Cambiar estos criterios no modifica sesiones pasadas: cada sesión guarda los criterios vigentes.")
            }
        }
        .navigationTitle(exercise?.name ?? "Ejercicio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() } }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let fmt = model.loadFormatter
        config = model.routines.effectiveConfig(for: item) ?? ProgressionConfig()
        hasRIR = config.targetRIR != nil
        rir = config.targetRIR ?? 2
        initialWeightText = fmt.editable(config.initialWeight)
        incrementText = fmt.editable(config.increment)
        availableText = (config.availableWeights ?? []).map { fmt.editable($0) }.joined(separator: "; ")
        restSeconds = item.restSeconds ?? model.repository.exercise(id: item.exerciseId)?.defaultRestSeconds ?? model.settings.defaultRestSeconds
        notes = item.notes
        supersetGroup = item.supersetGroup ?? 0
    }

    private func save() {
        let fmt = model.loadFormatter
        var updated = config
        updated.targetRIR = hasRIR ? rir : nil
        updated.initialWeight = initialWeightText.isEmpty ? nil : fmt.parse(initialWeightText)
        if let inc = fmt.parse(incrementText), inc > 0 { updated.increment = inc }
        let weights = availableText
            .split(separator: ";")
            .compactMap { fmt.parse(String($0)) }
        updated.availableWeights = weights.isEmpty ? nil : weights

        var newItem = item
        newItem.progressionOverride = updated
        newItem.restSeconds = restSeconds
        newItem.notes = notes
        newItem.supersetGroup = supersetGroup == 0 ? nil : supersetGroup
        let ok = model.perform {
            try model.routines.updateRoutineExercise(newItem)
            if applyToExercise { try model.catalog.updateProgression(exerciseId: item.exerciseId, config: updated) }
        }
        if ok != nil { dismiss() }
    }
}
