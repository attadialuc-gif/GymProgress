import GymCore
import GymStore
import SwiftUI

/// Home (stage 3 scope): resume banner, recommendations for the next workout, last session.
/// Calendar, streaks, records and volume summaries are added in stage 5.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        let now = model.now()
        let open = model.workout.openSession()
        let routine = nextRoutine(now: now)
        let previews = routine.map { model.workout.previewRecommendations(routineId: $0.id, now: now) } ?? []
        let last = model.repository.sessions().last { $0.status == .completed }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let open {
                    Card(highlighted: true) {
                        Text("Entrenamiento en curso").font(.headline)
                        Text(open.routineNameSnapshot ?? "Entrenamiento libre").foregroundStyle(.secondary)
                        Button("Retomar") { model.selectedTab = .workout }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if let routine {
                    Card {
                        Text("Próximo entrenamiento").font(.caption).foregroundStyle(.secondary)
                        Text(routine.name).font(.title2.weight(.bold))
                        ForEach(previews, id: \.0.id) { entry in
                            let exercise = entry.1
                            let rec = entry.2
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: rec.actionSymbol).foregroundStyle(Theme.accent)
                                VStack(alignment: .leading) {
                                    Text(exercise.name).font(.subheadline.weight(.semibold))
                                    Text(line(rec)).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if open == nil {
                            Button {
                                if model.perform({ try model.workout.startSession(routineId: routine.id, now: model.now()) }) != nil {
                                    model.selectedTab = .workout
                                }
                            } label: {
                                Label("Comenzar", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    Card {
                        Text("Empezá creando una rutina").font(.headline)
                        Button("Ir a Rutinas") { model.selectedTab = .routines }
                    }
                }

                if let last {
                    Card {
                        Text("Última sesión").font(.caption).foregroundStyle(.secondary)
                        Text(last.routineNameSnapshot ?? "Entrenamiento libre").font(.headline)
                        Text(last.startedAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Inicio")
    }

    /// Scheduled routine for today, else the routine after the last one trained, else the first.
    private func nextRoutine(now: Date) -> RoutineTemplate? {
        let routines = model.repository.routines().filter { !$0.isArchived }
        let calendar = model.workout.calendar
        if let planned = Schedule.plannedRoutine(on: now, entries: model.repository.scheduleEntries(), calendar: calendar),
           let routine = routines.first(where: { $0.id == planned }) {
            return routine
        }
        if let lastId = model.repository.sessions().last(where: { $0.status == .completed })?.routineId,
           let index = routines.firstIndex(where: { $0.id == lastId }) {
            return routines[(index + 1) % routines.count]
        }
        return routines.first
    }

    private func line(_ rec: Recommendation) -> String {
        let fmt = model.loadFormatter
        if rec.action == .needsInitialTarget && rec.targetWeight == nil { return "Sin datos: definí un objetivo inicial" }
        return "\(rec.actionTitle) · \(fmt.load(rec.targetWeight, measurement: rec.measurement, loadMode: rec.context.loadMode)) × \(rec.amountsText)"
    }
}
