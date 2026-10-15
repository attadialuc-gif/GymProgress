import Charts
import GymCore
import GymStore
import SwiftUI

/// Home (section 9.1): next workout with its recommendations first, then week, streak, records,
/// volume and last session. Every number comes from recorded data.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showStreakInfo = false

    var body: some View {
        let _ = model.revision
        let now = model.now()
        let fmt = model.loadFormatter
        let open = model.workout.openSession()
        let routine = nextRoutine(now: now)
        let previews = routine.map { model.workout.previewRecommendations(routineId: $0.id, now: now) } ?? []
        let week = model.consistency.weekSummary(now: now)
        let streak = model.consistency.streak(now: now)
        let comparison = model.stats.comparison(.week, now: now)
        let records = model.stats.recentRecords(days: 30, now: now)
        let last = model.history.completedSessionSummaries(limit: 1).first

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

                nextWorkoutCard(routine: routine, previews: previews, canStart: open == nil)

                HStack(alignment: .top, spacing: 12) {
                    Card {
                        Text("Esta semana").font(.caption).foregroundStyle(.secondary)
                        BigNumber(text: "\(week.validSessions)/\(week.weeklyGoal)", caption: "entrenamientos")
                        ProgressView(value: week.goalFraction).tint(Theme.accent)
                        if week.goalMet {
                            Text("Objetivo cumplido. ¡Bien!").font(.caption).foregroundStyle(Theme.positive)
                        } else if week.planned > 0 {
                            Text("\(week.planned) días planificados").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Card {
                        HStack {
                            Text("Racha").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { showStreakInfo = true } label: { Image(systemName: "info.circle") }
                                .accessibilityLabel("Cómo se calcula la racha")
                        }
                        BigNumber(text: "\(streak.result.current)", caption: streak.result.mode == .weeklyPlan ? "semanas" : "días")
                        Text("Récord: \(streak.result.best)").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                Card {
                    Text("Volumen de la semana").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        BigNumber(text: "\(comparison.current.effectiveSets)", caption: "series efectivas")
                        Spacer()
                        BigNumber(text: fmt.weight(comparison.current.volume), caption: "volumen externo")
                    }
                    Text("Semana anterior: \(comparison.previous.effectiveSets) series · \(fmt.weight(comparison.previous.volume))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    WeeklySetsChart()
                }

                if !records.isEmpty {
                    Card {
                        Text("Récords recientes").font(.caption).foregroundStyle(.secondary)
                        ForEach(records) { item in
                            HStack {
                                Image(systemName: item.record.isEstimated ? "function" : "trophy.fill")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading) {
                                    Text(item.exerciseName).font(.subheadline.weight(.semibold))
                                    Text(recordText(item.record)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if let last {
                    Card {
                        Text("Última sesión").font(.caption).foregroundStyle(.secondary)
                        Text(last.session.routineNameSnapshot ?? "Entrenamiento libre").font(.headline)
                        Text("\(last.session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(last.effectiveSets) series")
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink { CalendarView() } label: {
                    Label("Calendario y plan semanal", systemImage: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Inicio")
        .alert("Racha", isPresented: $showStreakInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(streak.definition)
        }
    }

    @ViewBuilder
    private func nextWorkoutCard(routine: RoutineTemplate?, previews: [(RoutineExercise, Exercise, Recommendation)], canStart: Bool) -> some View {
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
                if canStart {
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
    }

    /// Scheduled routine for today, else the routine after the last one trained, else the first.
    private func nextRoutine(now: Date) -> RoutineTemplate? {
        let routines = model.repository.routines().filter { !$0.isArchived }
        if let planned = model.consistency.plannedRoutine(on: now), let routine = routines.first(where: { $0.id == planned }) {
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

    private func recordText(_ record: PersonalRecord) -> String {
        let fmt = model.loadFormatter
        let date = record.date.formatted(.dateTime.day().month(.abbreviated))
        switch record.kind {
        case .maxWeight: return "Peso máximo: \(fmt.weight(record.value)) · \(date)"
        case .maxRepsAtWeight: return "\(Int(record.value)) reps con \(fmt.weight(record.weight)) · \(date)"
        case .bestEstimatedOneRepMax: return "1RM estimado: \(fmt.weight(record.value)) (estimación) · \(date)"
        case .maxSessionVolume: return "Volumen en una sesión: \(fmt.weight(record.value)) · \(date)"
        }
    }
}

/// Effective sets per week, last 8 weeks (compact progression chart for Home).
private struct WeeklySetsChart: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = model.now()
        let cal = model.stats.calendar
        let start = cal.weekStart(of: now)
        let points: [(Date, Int)] = (0..<8).reversed().map { back in
            let s = cal.addDays(-7 * back, to: start)
            return (s, model.stats.totals(in: DateInterval(start: s, end: cal.addDays(7, to: s))).effectiveSets)
        }
        Chart(points, id: \.0) { point in
            BarMark(x: .value("Semana", point.0, unit: .weekOfYear), y: .value("Series", point.1))
                .foregroundStyle(Theme.accent)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 100)
        .accessibilityLabel("Series efectivas por semana, últimas 8 semanas")
    }
}
