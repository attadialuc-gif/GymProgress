import GymCore
import GymStore
import SwiftUI

/// Set table: number · load · reps (or seconds) · RIR · type · state, with last session's value
/// next to each set. Every edit is saved immediately.
struct SetTable: View {
    @Environment(AppModel.self) private var model
    let log: ExerciseLog
    let sets: [SetLog]
    let previous: PerformanceSummary?
    let onComplete: (SetLog) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Serie").frame(width: 44, alignment: .leading)
                Text(loadHeader).frame(maxWidth: .infinity, alignment: .leading)
                Text(log.snapshot.measurement == .duration ? "Seg." : "Reps").frame(width: 64)
                Text("RIR").frame(width: 52)
                Spacer().frame(width: 44)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(sets.enumerated()), id: \.element.id) { position, set in
                SetRow(
                    log: log,
                    entry: set,
                    label: label(for: set, position: position),
                    previous: previousText(for: set),
                    onComplete: { onComplete(set) }
                )
            }
        }
    }

    private var loadHeader: String {
        let unit = model.settings.weightUnit.rawValue
        switch log.snapshot.measurement {
        case .bodyweightReps: return "Lastre (+) / asist. (−) \(unit)"
        case .weightReps, .duration: return log.snapshot.loadMode == .perSide ? "Peso por lado (\(unit))" : "Peso (\(unit))"
        }
    }

    private func label(for set: SetLog, position: Int) -> String {
        if set.kind == .warmup { return "C" }
        let workingIndex = sets.filter { $0.kind != .warmup }.firstIndex { $0.id == set.id } ?? position
        return "\(workingIndex + 1)"
    }

    private func previousText(for set: SetLog) -> String? {
        guard set.kind == .working, let previous else { return nil }
        let working = sets.filter { $0.kind == .working }
        guard let i = working.firstIndex(where: { $0.id == set.id }), i < previous.sets.count else { return nil }
        let p = previous.sets[i]
        return "Antes: \(model.loadFormatter.editable(p.load)) × \(p.amount)"
    }
}

private struct SetRow: View {
    @Environment(AppModel.self) private var model
    let log: ExerciseLog
    let entry: SetLog
    let label: String
    let previous: String?
    let onComplete: () -> Void

    @State private var loadText = ""
    @State private var amountText = ""
    @State private var warning: String?
    @State private var loaded = false

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
                    .onChange(of: loadText) { _, new in commitLoad(new) }
                    .accessibilityLabel("Peso de la serie \(label)")

                TextField(placeholderAmount, text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .onChange(of: amountText) { _, new in commitAmount(new) }
                    .accessibilityLabel(isDuration ? "Segundos de la serie \(label)" : "Repeticiones de la serie \(label)")

                Menu {
                    Button("Sin registrar") { updateRIR(nil) }
                    ForEach(0...5, id: \.self) { value in
                        Button("RIR \(value)") { updateRIR(Double(value)) }
                    }
                } label: {
                    Text(entry.rir.map { GymFormat.number($0) } ?? "–")
                        .frame(width: 52, height: 36)
                        .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("RIR de la serie \(label): \(entry.rir.map { GymFormat.number($0) } ?? "sin registrar")")

                Button {
                    if done {
                        model.perform { try model.workout.reopenSet(setId: entry.id) }
                    } else {
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
            Button("Quitar serie", role: .destructive) { model.perform { try model.workout.removeSet(setId: entry.id) } }
            Button(entry.kind == .warmup ? "Marcar como efectiva" : "Marcar como calentamiento") {
                var s = entry
                s.kind = entry.kind == .warmup ? .working : .warmup
                model.perform { try model.workout.updateSet(s) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: entry) { _, _ in syncFromModel() }
    }

    private var placeholderLoad: String {
        isBodyweight ? "0" : (isDuration ? "–" : "kg")
    }

    private var placeholderAmount: String {
        if isDuration { return entry.targetSeconds.map(String.init) ?? "s" }
        return entry.targetReps.map(String.init) ?? "reps"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        syncFromModel()
    }

    /// Pulls values written by "Aceptar" / "Copiar" into the text fields.
    private func syncFromModel() {
        let fmt = model.loadFormatter
        let loadValue: Double? = isBodyweight ? (entry.addedWeight != nil || entry.assistance != nil ? entry.performed.netAddedLoad : nil) : entry.weight
        let newLoad = fmt.editable(loadValue)
        if fmt.parse(loadText) != loadValue { loadText = newLoad }
        let amount = isDuration ? entry.seconds : entry.reps
        let newAmount = amount.map(String.init) ?? ""
        if WeightParser.parseInt(amountText) != amount { amountText = newAmount }
    }

    private func commitLoad(_ text: String) {
        let fmt = model.loadFormatter
        var s = entry
        if isBodyweight {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
            let magnitude = fmt.parse(negative ? String(trimmed.dropFirst()) : trimmed)
            if trimmed.isEmpty { s.addedWeight = nil; s.assistance = nil }
            else if let m = magnitude {
                s.addedWeight = negative ? nil : (m > 0 ? m : nil)
                s.assistance = negative ? m : nil
            } else { return }
        } else {
            if text.isEmpty { s.weight = nil }
            else if let v = fmt.parse(text) { s.weight = v } else { return }
        }
        save(s)
    }

    private func commitAmount(_ text: String) {
        var s = entry
        let value = text.isEmpty ? nil : WeightParser.parseInt(text)
        if !text.isEmpty && value == nil { return }
        if isDuration { s.seconds = value } else { s.reps = value }
        save(s)
    }

    private func updateRIR(_ value: Double?) {
        var s = entry
        s.rir = value
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
