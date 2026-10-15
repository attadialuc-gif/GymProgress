import GymCore
import GymStore
import SwiftUI

/// History of one exercise + the recommendation for the next session (computed from recorded data).
struct ExerciseHistoryView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: UUID

    var body: some View {
        let _ = model.revision
        let fmt = model.loadFormatter
        let entries = model.history.exerciseHistory(exerciseId: exerciseId)
        let next = model.workout.previewRecommendation(exerciseId: exerciseId, now: model.now())
        let records = PersonalRecords.compute(entries.map(\.performance), oneRepMax: model.settings.oneRepMax)

        List {
            if let next {
                Section("Próxima sesión") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(next.actionTitle, systemImage: next.actionSymbol)
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        if next.targetWeight != nil {
                            Text("\(fmt.load(next.targetWeight, measurement: next.measurement, loadMode: next.context.loadMode)) × \(next.amountsText)")
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                        Text(next.reasonText).font(.subheadline)
                        Text("Tendencia: \(next.trend.label)").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if records.maxWeight != nil {
                Section("Récords") {
                    if let r = records.maxWeight {
                        LabeledContent("Peso máximo (real)", value: fmt.weight(r.value))
                    }
                    if let r = records.bestEstimatedOneRepMax {
                        LabeledContent("Mejor 1RM estimado", value: "\(fmt.weight(r.value)) (estimado)")
                    }
                    if let r = records.maxSessionVolume {
                        LabeledContent("Mayor volumen en una sesión", value: fmt.weight(r.value))
                    }
                }
            }

            Section("Sesiones") {
                if entries.isEmpty {
                    Text("Todavía no hay sesiones registradas.").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.session.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            if entry.session.isAtypical || entry.log.isAtypical { Badge(text: "Atípica", color: .gray) }
                            if let context = [entry.log.equipmentLabel, entry.log.variantLabel].compactMap({ $0 }).first {
                                Badge(text: context, color: .secondary)
                            }
                            Spacer()
                            if let decision = entry.decision { Badge(text: decision.kind.label, color: .secondary) }
                        }
                        ForEach(entry.sets.filter { $0.status == .completed }) { set in
                            Text(setLine(set, measurement: entry.log.snapshot.measurement, loadMode: entry.log.snapshot.loadMode))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(set.kind == .warmup ? .secondary : .primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(model.repository.exercise(id: exerciseId)?.name ?? "Historial")
    }

    private func setLine(_ set: SetLog, measurement: MeasurementType, loadMode: LoadMode) -> String {
        let fmt = model.loadFormatter
        let prefix = set.kind == .warmup ? "Calentamiento · " : ""
        let load: Double? = measurement == .bodyweightReps ? set.performed.netAddedLoad : set.weight
        let amount = measurement == .duration ? "\(set.seconds ?? 0) s" : "\(set.reps ?? 0)"
        let rir = set.rir.map { " · RIR \(GymFormat.number($0))" } ?? ""
        return "\(prefix)\(fmt.load(load, measurement: measurement, loadMode: loadMode)) × \(amount)\(rir)"
    }
}

/// Progress tab (stage 3: exercises with history; charts arrive in stage 6).
struct ProgressHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        // Only exercises with at least one completed session (open/discarded sessions are not history).
        let withHistory = model.repository.exercises().filter { !model.history.exerciseHistory(exerciseId: $0.id).isEmpty }
        List {
            if withHistory.isEmpty {
                ContentUnavailableView("Sin historial", systemImage: "chart.line.uptrend.xyaxis", description: Text("Completá un entrenamiento para ver tu progreso."))
            }
            ForEach(withHistory) { exercise in
                NavigationLink(exercise.name) { ExerciseHistoryView(exerciseId: exercise.id) }
            }
        }
        .navigationTitle("Progreso")
    }
}
