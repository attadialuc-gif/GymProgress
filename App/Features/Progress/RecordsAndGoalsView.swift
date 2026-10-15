import GymCore
import GymStore
import SwiftUI

/// Records (real vs estimated, visually separated) and goals with progress (section 9.6).
struct RecordsAndGoalsView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewGoal = false

    var body: some View {
        let _ = model.revision
        let now = model.now()
        let fmt = model.loadFormatter
        let goals = model.stats.goalProgress(now: now)
        let exercises = model.repository.exercises().filter { !model.history.exerciseHistory(exerciseId: $0.id).isEmpty }

        List {
            Section {
                if goals.isEmpty { Text("Sin objetivos. Agregá uno para seguir tu progreso.").foregroundStyle(.secondary) }
                ForEach(goals) { progress in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.repository.exercise(id: progress.goal.exerciseId)?.name ?? "Ejercicio").font(.headline)
                            Spacer()
                            if progress.achieved { Badge(text: "Logrado", color: Theme.positive) }
                        }
                        Text(goalText(progress.goal, fmt: fmt)).font(.subheadline)
                        ProgressView(value: progress.fraction).tint(Theme.accent)
                        Text(progress.current.map { "Actual: \(value($0, metric: progress.goal.metric, fmt: fmt))" } ?? "Todavía sin datos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button { model.perform { try model.repository.deleteGoal(id: progress.goal.id) } } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            } header: {
                Text("Objetivos")
            }

            ForEach(exercises) { exercise in
                let records = model.stats.records(exerciseId: exercise.id)
                Section(exercise.name) {
                    if let r = records.maxWeight {
                        LabeledContent("Peso máximo", value: "\(fmt.weight(r.value)) · \(r.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if let r = records.maxSessionVolume {
                        LabeledContent("Mayor volumen en una sesión", value: fmt.weight(r.value))
                    }
                    ForEach(records.maxRepsAtWeight.suffix(3), id: \.self) { r in
                        LabeledContent("Más reps con \(fmt.weight(r.weight))", value: "\(Int(r.value))")
                    }
                    if let r = records.bestEstimatedOneRepMax {
                        LabeledContent {
                            Text("\(fmt.weight(r.value))").italic()
                        } label: {
                            HStack {
                                Text("1RM estimado")
                                Badge(text: "Estimación", color: .secondary)
                                HelpButton(title: "1RM estimado", text: MetricHelp.oneRepMax)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Récords y objetivos")
        .toolbar {
            Button { showNewGoal = true } label: { Label("Nuevo objetivo", systemImage: "plus") }
        }
        .sheet(isPresented: $showNewGoal) {
            NavigationStack { NewGoalForm() }
        }
        .onAppear { model.perform { try model.stats.refreshGoals(now: model.now()) } }
    }

    private func goalText(_ goal: Goal, fmt: LoadFormatter) -> String {
        let date = goal.targetDate.map { " para el \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        switch goal.metric {
        case .weight: return "Levantar \(fmt.weight(goal.value))\(date)"
        case .repsAtWeight: return "\(Int(goal.value)) reps con \(fmt.weight(goal.weight))\(date)"
        case .estimatedOneRepMax: return "1RM estimado de \(fmt.weight(goal.value))\(date)"
        case .sessionVolume: return "Volumen de \(fmt.weight(goal.value)) en una sesión\(date)"
        }
    }

    private func value(_ v: Double, metric: GoalMetric, fmt: LoadFormatter) -> String {
        metric == .repsAtWeight ? "\(Int(v)) reps" : fmt.weight(v)
    }
}

private struct NewGoalForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exerciseId: UUID?
    @State private var metric: GoalMetric = .weight
    @State private var valueText = ""
    @State private var weightText = ""
    @State private var hasDate = false
    @State private var date = Date()

    var body: some View {
        let exercises = model.repository.exercises().filter { !$0.isArchived && $0.measurement == .weightReps }
        let fmt = model.loadFormatter
        Form {
            Picker("Ejercicio", selection: $exerciseId) {
                Text("Elegí…").tag(UUID?.none)
                ForEach(exercises) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Métrica", selection: $metric) {
                Text("Peso máximo").tag(GoalMetric.weight)
                Text("Repeticiones con un peso").tag(GoalMetric.repsAtWeight)
                Text("1RM estimado").tag(GoalMetric.estimatedOneRepMax)
                Text("Volumen en una sesión").tag(GoalMetric.sessionVolume)
            }
            if metric == .repsAtWeight {
                TextField("Peso (\(model.settings.weightUnit.rawValue))", text: $weightText).keyboardType(.decimalPad)
                TextField("Repeticiones", text: $valueText).keyboardType(.numberPad)
            } else {
                TextField("Valor (\(model.settings.weightUnit.rawValue))", text: $valueText).keyboardType(.decimalPad)
            }
            Toggle("Fecha objetivo", isOn: $hasDate)
            if hasDate { DatePicker("Fecha", selection: $date, displayedComponents: .date) }
        }
        .navigationTitle("Nuevo objetivo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    guard let exerciseId else { return }
                    let value = metric == .repsAtWeight ? WeightParser.parseInt(valueText).map(Double.init) : fmt.parse(valueText)
                    guard let value, value > 0 else { return }
                    let goal = Goal(
                        exerciseId: exerciseId,
                        metric: metric,
                        value: value,
                        weight: metric == .repsAtWeight ? fmt.parse(weightText) : nil,
                        targetDate: hasDate ? date : nil,
                        createdAt: model.now()
                    )
                    if model.perform({ try model.repository.upsertGoal(goal) }) != nil { dismiss() }
                }
                .disabled(exerciseId == nil || valueText.isEmpty)
            }
        }
    }
}
