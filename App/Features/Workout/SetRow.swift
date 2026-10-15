import GymCore
import GymStore
import SwiftUI

/// One set: typed values are saved when the field loses focus or on submit (not per keystroke),
/// and always right before completing the set, so a tap on ✓ never loses what was typed.
struct SetRow: View {
    @Environment(AppModel.self) private var model
    let log: ExerciseLog
    let entry: SetLog
    let label: String
    let previous: String?
    let onComplete: () -> Void

    private enum Field: Hashable { case load, amount }

    @State private var loadText = ""
    @State private var amountText = ""
    @State private var warning: String?
    @State private var loaded = false
    @State private var confirmRemove = false
    @FocusState private var focused: Field?

    private var isDuration: Bool { log.snapshot.measurement == .duration }
    private var isBodyweight: Bool { log.snapshot.measurement == .bodyweightReps }
    private var done: Bool { entry.status == .completed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.headline.monospacedDigit())
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(entry.kind == .warmup ? .secondary : .primary)

                TextField(placeholderLoad, text: $loadText)
                    .keyboardType(isBodyweight ? .numbersAndPunctuation : .decimalPad)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .focused($focused, equals: .load)
                    .onSubmit { commitTexts() }
                    .accessibilityLabel("Peso de la serie \(label)")

                TextField(placeholderAmount, text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .focused($focused, equals: .amount)
                    .onSubmit { commitTexts() }
                    .accessibilityLabel(isDuration ? "Segundos de la serie \(label)" : "Repeticiones de la serie \(label)")

                effortMenu

                Button {
                    if done {
                        model.perform { try model.workout.reopenSet(setId: entry.id) }
                    } else {
                        commitTexts()
                        focused = nil
                        onComplete()
                    }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundStyle(done ? Theme.positive : .secondary)
                }
                .frame(width: 44)
                .accessibilityLabel(done ? "Serie \(label) completada; tocá para reabrir" : "Completar serie \(label)")
            }
            HStack(spacing: 8) {
                if let previous { Text(previous) }
                if let target = entry.targetReps, !isDuration { Text("Objetivo: \(target)").foregroundStyle(Theme.accent) }
                if let target = entry.targetSeconds, isDuration { Text("Objetivo: \(target) s").foregroundStyle(Theme.accent) }
                if let warning { Text(warning).foregroundStyle(Theme.caution) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 44)
        }
        .padding(.vertical, 4)
        .opacity(done ? 0.75 : 1)
        .contextMenu {
            Button("Quitar serie", role: .destructive) { confirmRemove = true }
            Button(entry.kind == .warmup ? "Marcar como efectiva" : "Marcar como calentamiento") {
                var s = entry
                s.kind = entry.kind == .warmup ? .working : .warmup
                model.perform { try model.workout.updateSet(s) }
            }
        }
        .confirmationDialog("¿Quitar la serie \(label)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Quitar serie", role: .destructive) { model.perform { try model.workout.removeSet(setId: entry.id) } }
        }
        .onAppear(perform: load)
        .onChange(of: entry) { _, _ in syncFromModel() }
        .onChange(of: focused) { old, _ in
            if old != nil { commitTexts() }
        }
        .onDisappear { commitTexts() }
    }

    /// RIR in one tap (0–10) or RPE (6–10). Optional; feeds the engine's effort check.
    private var effortMenu: some View {
        Menu {
            Button("Sin registrar") { updateEffort(rir: nil, rpe: nil) }
            Section("RIR (repeticiones en reserva)") {
                ForEach(0...10, id: \.self) { value in
                    Button("RIR \(value)") { updateEffort(rir: Double(value), rpe: nil) }
                }
            }
            Section("RPE") {
                ForEach([6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button("RPE \(GymFormat.number(value))") { updateEffort(rir: nil, rpe: value) }
                }
            }
        } label: {
            Text(effortLabel)
                .font(.subheadline.monospacedDigit())
                .frame(width: 52, height: 36)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Esfuerzo de la serie \(label): \(effortLabel == "–" ? "sin registrar" : effortLabel)")
    }

    private var effortLabel: String {
        if let rir = entry.rir { return GymFormat.number(rir) }
        if let rpe = entry.rpe { return "@\(GymFormat.number(rpe))" }
        return "–"
    }

    private var placeholderLoad: String {
        isBodyweight ? "0" : (isDuration ? "–" : model.settings.weightUnit.rawValue)
    }

    private var placeholderAmount: String {
        if isDuration { return entry.targetSeconds.map(String.init) ?? "s" }
        return entry.targetReps.map(String.init) ?? "reps"
    }

    private var storedLoad: Double? {
        isBodyweight ? (entry.addedWeight != nil || entry.assistance != nil ? entry.performed.netAddedLoad : nil) : entry.weight
    }

    private var storedAmount: Int? { isDuration ? entry.seconds : entry.reps }

    private func loadDisplay(_ value: Double?) -> String {
        guard let value else { return "" }
        let fmt = model.loadFormatter
        return isBodyweight && value < 0 ? "-" + fmt.editable(-value) : fmt.editable(value)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        syncFromModel()
    }

    /// Pulls values written elsewhere ("Aceptar", "Copiar") into the fields. Never writes back:
    /// displaying a value can't change what is stored.
    private func syncFromModel() {
        if focused != .load { loadText = loadDisplay(storedLoad) }
        if focused != .amount { amountText = storedAmount.map(String.init) ?? "" }
    }

    /// Saves typed text if it differs from what is stored (by its displayed form, so rounding for
    /// display never rewrites a stored value).
    private func commitTexts() {
        var s = entry
        if loadText != loadDisplay(storedLoad) {
            let fmt = model.loadFormatter
            let trimmed = loadText.trimmingCharacters(in: .whitespaces)
            if isBodyweight {
                let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
                if trimmed.isEmpty {
                    s.addedWeight = nil
                    s.assistance = nil
                } else if let m = fmt.parse(negative ? String(trimmed.dropFirst()) : trimmed) {
                    s.addedWeight = negative ? nil : (m > 0 ? m : nil)
                    s.assistance = negative ? m : nil
                } else {
                    warning = "Peso inválido: usá coma o punto decimal."
                }
            } else if trimmed.isEmpty {
                s.weight = nil
            } else if let v = fmt.parse(trimmed) {
                s.weight = v
            } else {
                warning = "Peso inválido: usá coma o punto decimal."
            }
        }
        if amountText != (storedAmount.map(String.init) ?? "") {
            if amountText.isEmpty {
                if isDuration { s.seconds = nil } else { s.reps = nil }
            } else if let v = WeightParser.parseInt(amountText) {
                if isDuration { s.seconds = v } else { s.reps = v }
            } else {
                warning = "Ingresá un número entero."
            }
        }
        save(s)
    }

    private func updateEffort(rir: Double?, rpe: Double?) {
        var s = entry
        s.rir = rir
        s.rpe = rpe
        save(s)
    }

    private func save(_ s: SetLog) {
        guard s != entry else { return }
        let issues = SetValidator.validate(weight: s.weight, reps: s.reps, seconds: s.seconds, rir: s.rir, rpe: s.rpe)
        warning = issues.compactMap { issue -> String? in
            if case let .warning(message) = issue { return message }
            return nil
        }.first
        model.perform { try model.workout.updateSet(s) }
    }
}
