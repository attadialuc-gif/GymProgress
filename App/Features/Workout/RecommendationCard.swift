import GymCore
import GymStore
import SwiftUI

/// Section 2.A: the most prominent element of the exercise screen, above the set table.
/// It only *presents* what the engine returned (no business logic here).
struct RecommendationCard: View {
    let recommendation: Recommendation
    let decision: RecommendationDecision?
    let formatter: LoadFormatter
    let onAccept: () -> Void
    let onModify: () -> Void
    let onIgnore: () -> Void
    let onCopyPrevious: () -> Void
    let onSetInitialTarget: () -> Void

    var body: some View {
        Card(highlighted: decision == nil) {
            header
            lastSession
            Divider()
            target
            suggested
            Text(recommendation.reasonText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !recommendation.conditions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.conditions, id: \.self) { condition in
                        Label(condition, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.caution)
                    }
                }
            }
            ForEach(recommendation.notes, id: \.self) { note in
                Label(note, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let reference = recommendation.nonEquivalentReference {
                Label("Referencia no equivalente (otro contexto): \(formatter.load(reference.workingLoad, measurement: reference.measurement, loadMode: reference.context.loadMode)) × \(GymFormat.list(reference.amounts))", systemImage: "arrow.triangle.branch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            buttons
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Label(recommendation.actionTitle, systemImage: recommendation.actionSymbol)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Spacer()
            if recommendation.confidence == .conditional {
                Badge(text: "Condicionada", color: Theme.caution)
            }
            if let decision {
                Badge(text: decision.kind.label, color: Theme.positive)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lastSession: some View {
        if let last = recommendation.lastPerformance {
            VStack(alignment: .leading, spacing: 2) {
                Text("Última sesión · \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(formatter.load(last.workingLoad, measurement: last.measurement, loadMode: last.context.loadMode)) × \(GymFormat.list(last.amounts))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if last.sets.contains(where: { $0.rir != nil }) {
                    Text("RIR: " + last.sets.map { $0.rir.map { GymFormat.number($0) } ?? "–" }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Sin sesión anterior comparable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var target: some View {
        let t = recommendation.target
        let range = recommendation.measurement == .duration ? "\(t.secondsMin)–\(t.secondsMax) s" : "\(t.repMin)–\(t.repMax)"
        let rir = t.targetRIR.map { " · RIR \($0)" } ?? ""
        return Text("Objetivo de hoy: \(t.sets) × \(range)\(rir)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var suggested: some View {
        if recommendation.targetWeight != nil || !recommendation.targetReps.isEmpty || recommendation.targetSeconds != nil {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                BigNumber(
                    text: formatter.load(recommendation.targetWeight, measurement: recommendation.measurement, loadMode: recommendation.context.loadMode),
                    caption: "Recomendado"
                )
                BigNumber(text: recommendation.amountsText, caption: recommendation.measurement == .duration ? "Segundos" : "Repeticiones")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recomendado: \(formatter.load(recommendation.targetWeight, measurement: recommendation.measurement, loadMode: recommendation.context.loadMode)), \(recommendation.amountsText)")
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if recommendation.action == .needsInitialTarget && recommendation.targetWeight == nil {
            HStack {
                Button("Definir objetivo inicial", action: onSetInitialTarget)
                    .buttonStyle(.borderedProminent)
                Button("Ignorar", action: onIgnore)
                    .buttonStyle(.bordered)
            }
        } else {
            HStack {
                Button("Aceptar", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Precarga el peso recomendado en las series")
                Button("Modificar", action: onModify)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Ajustá peso y repeticiones objetivo de hoy")
                Button("Ignorar", action: onIgnore)
                    .buttonStyle(.bordered)
                    .accessibilityHint("No precarga nada")
            }
            .controlSize(.large)
        }
        if decision?.kind == .ignored || recommendation.action == .needsInitialTarget {
            Button(action: onCopyPrevious) {
                Label("Copiar cargas anteriores", systemImage: "doc.on.doc")
            }
            .font(.subheadline)
            .disabled(recommendation.lastPerformance == nil && recommendation.nonEquivalentReference == nil)
        }
    }
}

extension DecisionKind {
    var label: String {
        switch self {
        case .accepted: "Aceptada"
        case .modified: "Modificada"
        case .ignored: "Ignorada"
        }
    }
}

/// Quick editor for "Modificar": +/− with the exercise increment.
struct ModifyRecommendationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recommendation: Recommendation
    let increment: Double
    let formatter: LoadFormatter
    let onSave: (Double?, [Int], [Int]?) -> Void

    @State private var weight: Double = 0
    @State private var amounts: [Int] = []
    @State private var loaded = false

    private var isDuration: Bool { recommendation.measurement == .duration }

    var body: some View {
        Form {
            Section("Peso objetivo") {
                HStack {
                    Button {
                        let floor = recommendation.measurement == .bodyweightReps ? -500.0 : 0
                        weight = max(floor, LoadMath.normalized(weight - increment))
                    } label: { Image(systemName: "minus.circle.fill") }
                        .accessibilityLabel("Restar \(formatter.weight(increment))")
                    Spacer()
                    Text(formatter.load(weight, measurement: recommendation.measurement, loadMode: recommendation.context.loadMode))
                        .font(.title.weight(.bold).monospacedDigit())
                    Spacer()
                    Button { weight = LoadMath.normalized(weight + increment) } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Sumar \(formatter.weight(increment))")
                }
                .font(.title)
                .buttonStyle(.borderless)
            }
            Section(isDuration ? "Segundos por serie" : "Repeticiones por serie") {
                ForEach(amounts.indices, id: \.self) { i in
                    Stepper("Serie \(i + 1): \(amounts[i])\(isDuration ? " s" : "")", value: $amounts[i], in: 0...(isDuration ? 3600 : 100), step: isDuration ? 5 : 1)
                }
                Button("Agregar serie") { amounts.append(amounts.last ?? recommendation.target.repMin) }
                if amounts.count > 1 {
                    Button("Quitar serie", role: .destructive) { amounts.removeLast() }
                }
            }
        }
        .navigationTitle("Modificar objetivo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Usar") {
                    if isDuration { onSave(weight, [], amounts) } else { onSave(weight, amounts, nil) }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            weight = recommendation.targetWeight ?? recommendation.lastPerformance?.workingLoad ?? 0
            let base = isDuration ? (recommendation.targetSeconds ?? []) : recommendation.targetReps
            amounts = base.isEmpty
                ? Array(repeating: isDuration ? recommendation.target.secondsMin : recommendation.target.repMin, count: recommendation.target.sets)
                : base
        }
    }
}
