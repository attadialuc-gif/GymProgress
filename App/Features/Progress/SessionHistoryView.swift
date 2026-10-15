import GymCore
import GymStore
import SwiftUI

/// Every finished workout, newest first.
struct SessionHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let summaries = model.history.completedSessionSummaries()
        let fmt = model.loadFormatter
        List {
            if summaries.isEmpty {
                ContentUnavailableView("Sin entrenamientos", systemImage: "calendar", description: Text("Los entrenamientos finalizados aparecen acá."))
            }
            ForEach(summaries) { summary in
                NavigationLink { SessionDetailView(sessionId: summary.session.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(summary.session.routineNameSnapshot ?? "Entrenamiento libre").font(.headline)
                            if summary.session.isAtypical { Badge(text: "Atípica", color: .gray) }
                        }
                        Text(summary.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(summary.effectiveSets) series · \(fmt.weight(summary.volume)) de volumen externo · \(Duration.seconds(summary.duration).formatted(.time(pattern: .hourMinute)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Entrenamientos")
    }
}

/// A finished workout: exercises in real execution order with their sets and decisions.
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionId: UUID

    var body: some View {
        let _ = model.revision
        let fmt = model.loadFormatter
        if let session = model.repository.session(id: sessionId) {
            let logs = model.repository.exerciseLogs(sessionId: sessionId).sorted {
                ($0.executionOrder ?? Int.max, $0.plannedOrder) < ($1.executionOrder ?? Int.max, $1.plannedOrder)
            }
            List {
                Section {
                    LabeledContent("Inicio", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Duración (sin pausas)", value: Duration.seconds(session.elapsed(at: session.endedAt ?? session.startedAt)).formatted(.time(pattern: .hourMinute)))
                    if !session.notes.isEmpty { Text(session.notes) }
                }
                ForEach(logs) { log in
                    Section {
                        let sets = model.repository.setLogs(exerciseLogId: log.id)
                        ForEach(sets) { set in
                            HStack {
                                Text(set.kind == .warmup ? "C" : "\(set.index + 1)").frame(width: 24, alignment: .leading)
                                if set.status == .completed {
                                    let load: Double? = log.snapshot.measurement == .bodyweightReps ? set.performed.netAddedLoad : set.weight
                                    Text("\(fmt.load(load, measurement: log.snapshot.measurement, loadMode: log.snapshot.loadMode)) × \(log.snapshot.measurement == .duration ? "\(set.seconds ?? 0) s" : "\(set.reps ?? 0)")")
                                        .monospacedDigit()
                                    if let rir = set.rir { Text("RIR \(GymFormat.number(rir))").foregroundStyle(.secondary) }
                                } else {
                                    Text("No realizada").foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        if let decision = model.repository.decision(exerciseLogId: log.id) {
                            Text("Recomendación \(decision.kind.label.lowercased()): \(decision.recommended.reasonText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            Text(log.snapshot.name)
                            if let label = [log.equipmentLabel, log.variantLabel].compactMap({ $0 }).first { Text("· \(label)") }
                            if log.isAtypical { Text("· atípico") }
                        }
                    }
                }
            }
            .navigationTitle(session.routineNameSnapshot ?? "Entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
