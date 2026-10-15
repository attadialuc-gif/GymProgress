import Charts
import GymCore
import GymStore
import SwiftUI

/// Definitions shown next to each metric (section 9.4: every indicator explains itself).
enum MetricHelp {
    static let effectiveSets = "Series efectivas: series de trabajo completadas con peso y repeticiones válidos. El calentamiento no cuenta."
    static let volume = "Volumen externo: suma de peso × repeticiones de las series efectivas. En mancuernas o unilaterales se cuenta el total de ambos lados. Más volumen no implica necesariamente más fuerza o hipertrofia."
    static let oneRepMax = "1RM estimado: cálculo con la fórmula elegida en Ajustes a partir de series de hasta el tope de repeticiones configurado. Es una estimación, no una medición."
    static let indirect = "Series indirectas: series de ejercicios donde el músculo es secundario, multiplicadas por el factor de participación (0,5 por defecto). Se muestran aparte de las directas."
    static let validSession = "Entrenamiento válido: finalizado y con al menos el mínimo de series efectivas configurado."
}

struct HelpButton: View {
    let title: String
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { Image(systemName: "questionmark.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel("Qué significa \(title)")
            .alert(title, isPresented: $shown) { Button("OK", role: .cancel) {} } message: { Text(text) }
    }
}

enum PeriodChoice: String, CaseIterable, Identifiable {
    case week, last30Days, calendarMonth, last90Days, calendarYear, last12Months, custom
    var id: String { rawValue }

    func period(customStart: Date, customEnd: Date) -> StatsPeriod {
        switch self {
        case .week: .week
        case .last30Days: .last30Days
        case .calendarMonth: .calendarMonth
        case .last90Days: .last90Days
        case .calendarYear: .calendarYear
        case .last12Months: .last12Months
        case .custom: .custom(DateInterval(start: min(customStart, customEnd), end: max(customStart, customEnd)))
        }
    }

    var label: String { period(customStart: .now, customEnd: .now).label }
}

/// Progress tab (section 9.4). Complements the recommendation system; never needed to know what to do today.
struct ProgressHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var choice: PeriodChoice = .last30Days
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var routineId: UUID?

    var body: some View {
        let _ = model.revision
        let now = model.now()
        let period = choice.period(customStart: customStart, customEnd: customEnd)
        let comparison = model.stats.comparison(period, now: now, routineId: routineId)
        let interval = period.interval(now: now, calendar: model.stats.calendar)
        let fmt = model.loadFormatter
        let withHistory = model.repository.exercises().filter { !model.history.exerciseHistory(exerciseId: $0.id).isEmpty }

        List {
            Section {
                Picker("Período", selection: $choice) {
                    ForEach(PeriodChoice.allCases) { Text($0.label).tag($0) }
                }
                if choice == .custom {
                    DatePicker("Desde", selection: $customStart, displayedComponents: .date)
                    DatePicker("Hasta", selection: $customEnd, displayedComponents: .date)
                }
                Picker("Rutina", selection: $routineId) {
                    Text("Todas").tag(UUID?.none)
                    ForEach(model.repository.routines()) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Section {
                ComparisonRow(title: "Entrenamientos válidos", help: MetricHelp.validSession, current: Double(comparison.current.validSessions), previous: Double(comparison.previous.validSessions)) { "\(Int($0))" }
                ComparisonRow(title: "Días entrenados", help: nil, current: Double(comparison.current.trainingDays), previous: Double(comparison.previous.trainingDays)) { "\(Int($0))" }
                ComparisonRow(title: "Series efectivas", help: MetricHelp.effectiveSets, current: Double(comparison.current.effectiveSets), previous: Double(comparison.previous.effectiveSets)) { "\(Int($0))" }
                ComparisonRow(title: "Volumen externo", help: MetricHelp.volume, current: comparison.current.volume, previous: comparison.previous.volume) { fmt.weight($0) }
            } header: {
                Text("\(period.label) vs. período anterior equivalente")
            }

            Section("Músculos") {
                NavigationLink { MuscleVolumeView(interval: interval, title: period.label) } label: {
                    Label("Series por grupo muscular", systemImage: "figure.arms.open")
                }
            }

            Section("Ejercicios") {
                if withHistory.isEmpty {
                    Text("Completá un entrenamiento para ver tu progreso.").foregroundStyle(.secondary)
                }
                ForEach(withHistory) { exercise in
                    NavigationLink(exercise.name) { ExerciseProgressView(exerciseId: exercise.id, interval: interval) }
                }
            }

            Section {
                NavigationLink { RecordsAndGoalsView() } label: { Label("Récords y objetivos", systemImage: "trophy") }
                NavigationLink { SessionHistoryView() } label: { Label("Entrenamientos realizados", systemImage: "calendar") }
            }
        }
        .navigationTitle("Progreso")
    }
}

private struct ComparisonRow: View {
    let title: String
    let help: String?
    let current: Double
    let previous: Double
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(title)
            if let help { HelpButton(title: title, text: help) }
            Spacer()
            VStack(alignment: .trailing) {
                Text(format(current)).font(.headline.monospacedDigit())
                Text("antes: \(format(previous))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Charts of one exercise: load, reps, estimated 1RM and volume per session (real data only).
struct ExerciseProgressView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: UUID
    let interval: DateInterval

    enum Metric: String, CaseIterable, Identifiable {
        case load = "Peso"
        case reps = "Repeticiones"
        case oneRepMax = "1RM estimado"
        case volume = "Volumen"
        var id: String { rawValue }
    }

    @State private var metric: Metric = .load

    var body: some View {
        let _ = model.revision
        let points = model.stats.exerciseSeries(exerciseId: exerciseId, in: interval)
        let fmt = model.loadFormatter
        List {
            Section {
                Picker("Métrica", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    Text("Sin sesiones en este período.").foregroundStyle(.secondary)
                } else {
                    Chart(points) { point in
                        if let value = value(point) {
                            LineMark(x: .value("Fecha", point.date), y: .value(metric.rawValue, value))
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Fecha", point.date), y: .value(metric.rawValue, value))
                                .foregroundStyle(point.isAtypical ? Color.gray : Theme.accent)
                        }
                    }
                    .frame(height: 220)
                    .accessibilityLabel("\(metric.rawValue) por sesión")
                }
            } footer: {
                switch metric {
                case .oneRepMax: Text(MetricHelp.oneRepMax)
                case .volume: Text(MetricHelp.volume)
                case .load: Text("Peso de trabajo: el más usado en las series efectivas de la sesión. Puntos grises: sesiones atípicas (no cuentan para tendencias).")
                case .reps: Text("Repeticiones totales en las series de trabajo de cada sesión.")
                }
            }

            Section("Sesiones") {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        if let label = point.contextLabel { Badge(text: label, color: .secondary) }
                        Spacer()
                        Text("\(fmt.weight(point.workingLoad)) · \(point.totalReps) reps").monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }

            Section {
                NavigationLink("Historial completo y recomendación") { ExerciseHistoryView(exerciseId: exerciseId) }
            }
        }
        .navigationTitle(model.repository.exercise(id: exerciseId)?.name ?? "Ejercicio")
    }

    private func value(_ p: ExercisePoint) -> Double? {
        let fmt = model.loadFormatter
        switch metric {
        case .load: return fmt.value(p.workingLoad)
        case .reps: return Double(p.totalReps)
        case .oneRepMax: return p.estimatedOneRepMax.map(fmt.value)
        case .volume: return fmt.value(p.volume)
        }
    }
}

/// Direct and indirect sets per muscle in the period, plus weekly evolution per muscle.
struct MuscleVolumeView: View {
    @Environment(AppModel.self) private var model
    let interval: DateInterval
    let title: String

    var body: some View {
        let volume = model.stats.muscleVolume(in: interval).sorted { $0.directSets > $1.directSets }
        List {
            Section {
                ForEach(volume, id: \.muscle) { item in
                    NavigationLink { MuscleWeeklyView(muscle: item.muscle) } label: {
                        HStack {
                            Text(item.muscle.label)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(item.directSets) directas").font(.subheadline.monospacedDigit())
                                Text("\(GymFormat.number(item.indirectSets, maxFractionDigits: 1)) indirectas · \(item.frequencyDays) días")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if volume.isEmpty { Text("Sin series en este período.").foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text(title)
                    HelpButton(title: "Series indirectas", text: MetricHelp.indirect)
                }
            } footer: {
                Text("Los objetivos de series semanales son individuales: la app no impone una cantidad ideal.")
            }
        }
        .navigationTitle("Grupos musculares")
    }
}

private struct MuscleWeeklyView: View {
    @Environment(AppModel.self) private var model
    let muscle: MuscleGroup

    var body: some View {
        let weeks = model.stats.weeklyDirectSets(muscle: muscle, weeks: 12, now: model.now())
        List {
            Chart(weeks, id: \.weekStart) { week in
                BarMark(x: .value("Semana", week.weekStart, unit: .weekOfYear), y: .value("Directas", week.directSets))
                    .foregroundStyle(Theme.accent)
                BarMark(x: .value("Semana", week.weekStart, unit: .weekOfYear), y: .value("Indirectas", week.indirectSets))
                    .foregroundStyle(Theme.accent.opacity(0.35))
            }
            .frame(height: 220)
            .accessibilityLabel("Series semanales de \(muscle.label), últimas 12 semanas")
            Text("Color pleno: series directas. Claro: indirectas estimadas (apiladas, se informan aparte).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(muscle.label)
    }
}
