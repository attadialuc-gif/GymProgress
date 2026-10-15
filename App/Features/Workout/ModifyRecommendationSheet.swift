import GymCore
import GymStore
import SwiftUI

/// Quick editor for "Modificar" (and for setting an initial target): the weight can be typed
/// (comma or dot) or nudged with +/− by the exercise increment; reps/seconds per set with steppers.
struct ModifyRecommendationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recommendation: Recommendation
    let increment: Double
    let formatter: LoadFormatter
    var title = "Modificar objetivo"
    let onSave: (Double?, [Int], [Int]?) -> Void

    @State private var weightText = ""
    @State private var amounts: [Int] = []
    @State private var loaded = false

    private var isDuration: Bool { recommendation.measurement == .duration }
    private var isBodyweight: Bool { recommendation.measurement == .bodyweightReps }

    /// Parsed weight in kg. Body weight accepts a leading "-" for assistance. Empty = no load.
    private var weight: Double? {
        let trimmed = weightText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let negative = isBodyweight && (trimmed.hasPrefix("-") || trimmed.hasPrefix("−"))
        guard let magnitude = formatter.parse(negative ? String(trimmed.dropFirst()) : trimmed) else { return nil }
        return negative ? -magnitude : magnitude
    }

    private var weightIsInvalid: Bool {
        !weightText.trimmingCharacters(in: .whitespaces).isEmpty && weight == nil
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button { nudge(-increment) } label: { Image(systemName: "minus.circle.fill") }
                        .accessibilityLabel("Restar \(formatter.weight(increment))")
                    TextField(isDuration ? "Sin carga" : formatter.unit.rawValue, text: $weightText)
                        .keyboardType(isBodyweight ? .numbersAndPunctuation : .decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title.weight(.bold).monospacedDigit())
                        .accessibilityLabel("Peso objetivo")
                    Button { nudge(increment) } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Sumar \(formatter.weight(increment))")
                }
                .font(.title)
                .buttonStyle(.borderless)
            } header: {
                Text(isBodyweight ? "Lastre (+) o asistencia (−)" : "Peso objetivo")
            } footer: {
                if weightIsInvalid {
                    Text("Número inválido. Usá coma o punto decimal (ej.: 61,5).").foregroundStyle(Theme.caution)
                } else {
                    Text(isDuration ? "Opcional: dejalo vacío si no usás carga." : "Podés escribir cualquier valor o usar ± \(formatter.weight(increment)).")
                }
            }

            Section(isDuration ? "Segundos por serie" : "Repeticiones por serie") {
                ForEach(Array(amounts.enumerated()), id: \.offset) { i, value in
                    Stepper(
                        "Serie \(i + 1): \(value)\(isDuration ? " s" : "")",
                        value: Binding(
                            get: { i < amounts.count ? amounts[i] : 0 },
                            set: { if i < amounts.count { amounts[i] = $0 } }
                        ),
                        in: 0...(isDuration ? 3600 : 100),
                        step: isDuration ? 5 : 1
                    )
                }
                Button("Agregar serie") {
                    amounts.append(amounts.last ?? (isDuration ? recommendation.target.secondsMin : recommendation.target.repMin))
                }
                if amounts.count > 1 {
                    Button("Quitar serie", role: .destructive) { amounts.removeLast() }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Usar") {
                    if isDuration { onSave(weight, [], amounts) } else { onSave(weight, amounts, nil) }
                    dismiss()
                }
                .disabled(weightIsInvalid || amounts.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        // Start from the recommendation, else the last comparable load; never invent a number.
        let start = recommendation.targetWeight ?? recommendation.lastPerformance?.workingLoad
        if let start, !(isDuration && LoadMath.key(start) == 0) {
            weightText = isBodyweight && start < 0 ? "-" + formatter.editable(-start) : formatter.editable(start)
        }
        let base = isDuration ? (recommendation.targetSeconds ?? []) : recommendation.targetReps
        amounts = base.isEmpty
            ? Array(repeating: isDuration ? recommendation.target.secondsMin : recommendation.target.repMin, count: recommendation.target.sets)
            : base
    }

    private func nudge(_ delta: Double) {
        let current = weight ?? 0
        let floor = isBodyweight ? -500.0 : 0
        let next = max(floor, LoadMath.normalized(current + delta))
        weightText = isBodyweight && next < 0 ? "-" + formatter.editable(-next) : formatter.editable(next)
    }
}
