import Charts
import GymCore
import GymStore
import SwiftUI

/// Definitions shown next to each metric (section 9.4: every indicator explains itself).
enum MetricHelp {
    static let effectiveSets = "Series efectivas: series de trabajo completadas con peso y repeticiones válidos. El calentamiento no cuenta."
    static let volume = "Volumen externo: suma de peso × repeticiones de las series efectivas. En mancuernas o unilaterales se cuenta el total de ambos lados. Más volumen no implica necesariamente más fuerza o hipertrofia."
    static let oneRepMax = "1RM estimado: cálculo con la fórmula elegida en Perfil a partir de series de hasta el tope de repeticiones configurado. Es una estimación, no una medición."
    static let indirect = "Series indirectas: series de ejercicios donde el músculo es secundario, multiplicadas por el factor de participación (0,5 por defecto). Se muestran aparte de las directas."
    static let validSession = "Entrenamiento válido: finalizado y con al menos el mínimo de series efectivas configurado."
    static let context = "Distintas máquinas o variantes no se comparan entre sí: cada una tiene su propia serie y sus récords. Si son equivalentes, vinculalas desde la pantalla del ejercicio durante un entrenamiento."
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
        let stats = model.stats
        let period = choice.period(customStart: customStart, customEnd: customEnd)
        let comparison = stats.comparison(period, now: now, routineId: routineId)
        let interval = period.interval(now: now, calendar: stats.calendar)
        let fmt = model.loadFormatter
        let ids = model.history.exerciseIdsWithCompletedHistory()
        let withHistory = model.repository.exercises().filter { ids.contains($0.id) }

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
                Text(comparison.isToDate
                     ? "\(period.label) a la fecha vs. los mismos días del período anterior"
                     : "\(period.label) vs. período anterior equivalente")
            }

            Section("Músculos") {
                NavigationLink { MuscleVolumeView(interval: interval, title: period.label, routineId: routineId) } label: {
                    Label("Series por grupo muscular", systemImage: "figure.arms.open")
                }
            }

            Section("Ejercicios") {
                if withHistory.isEmpty {
                    Text("Completá un entrenamiento para ver tu progreso.").foregroundStyle(.secondary)
                }
                ForEach(withHistory) { exercise in
                    NavigationLink(exercise.name) { ExerciseProgressView(exerciseId: exercise.id, interval: interval, routineId: routineId) }
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

/// Charts of one exercise in one comparability class: load, reps/seconds, estimated 1RM and volume
/// per session (real data only).
struct ExerciseProgressView: View {
    @Environment(AppModel.self) private var model
    let exerciseId: UUID
    let interval: DateInterval
    var routineId: UUID?

    enum Metric: String, CaseIterable, Identifiable {
        case load, amount, oneRepMax, volume
        var id: String { rawValue }
    }

    @State private var metric: Metric = .load
    @State private var classId: String?

    var body: some View {
        let _ = model.revision
        let stats = model.stats
        let classes = stats.contextClasses(exerciseId: exerciseId)
        let selected = classes.first { $0.id == classId } ?? classes.first
        let points = stats.exerciseSeries(exerciseId: exerciseId, in: interval, contextClass: selected, routineId: routineId)
        let measurement = points.first?.measurement ?? model.repository.exercise(id: exerciseId)?.measurement ?? .weightReps
        let metrics = Metric.allCases.filter { $0 != .oneRepMax || measurement == .weightReps }
        let fmt = model.loadFormatter

        List {
            if classes.count > 1 {
                Section {
                    Picker("Máquina / variante", selection: Binding(get: { selected?.id }, set: { classId = $0 })) {
                        ForEach(classes) { Text($0.label).tag(Optional($0.id)) }
                    }
                } footer: {
                    HStack(alignment: .top) {
                        Text("Cada contexto tiene su propio gráfico y récords.")
                        HelpButton(title: "Contextos", text: MetricHelp.context)
                    }
                }
            }

            Section {
                Picker("Métrica", selection: $metric) {
                    ForEach(metrics) { Text(title(for: $0, measurement: measurement)).tag($0) }
                }
                .pickerStyle(.segmented)
                let values = points.compactMap { p in value(p).map { (p, $0) } }
                if values.isEmpty {
                    Text(points.isEmpty ? "Sin sesiones en este período." : "Sin datos para esta métrica (por ejemplo, ninguna serie dentro del tope de repeticiones del 1RM).")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(values, id: \.0.id) { entry in
                        LineMark(x: .value("Fecha", entry.0.date), y: .value(title(for: metric, measurement: measurement), entry.1))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Fecha", entry.0.date), y: .value(title(for: metric, measurement: measurement), entry.1))
                            .foregroundStyle(entry.0.isAtypical ? Color.gray : Theme.accent)
                    }
                    .frame(height: 220)
                    .accessibilityLabel("\(title(for: metric, measurement: measurement)) por sesión")
                }
            } footer: {
                Text(footer(measurement: measurement))
            }

            Section("Sesiones") {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        if point.isAtypical { Badge(text: "Atípica", color: .gray) }
                        Spacer()
                        Text("\(fmt.load(point.workingLoad, measurement: point.measurement, loadMode: point.loadMode)) · \(amountText(point))")
                            .monospacedDigit()
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

    private func title(for metric: Metric, measurement: MeasurementType) -> String {
        switch metric {
        case .load: measurement == .bodyweightReps ? "Lastre" : "Peso"
        case .amount: measurement == .duration ? "Segundos" : "Repeticiones"
        case .oneRepMax: "1RM estimado"
        case .volume: measurement == .duration ? "Tiempo" : "Volumen"
        }
    }

    private func footer(measurement: MeasurementType) -> String {
        switch metric {
        case .oneRepMax: return MetricHelp.oneRepMax
        case .volume: return measurement == .duration ? "Tiempo total bajo carga de las series efectivas." : MetricHelp.volume
        case .load:
            return measurement == .bodyweightReps
                ? "Carga neta sobre el peso corporal: lastre (+) o asistencia (−). Puntos grises: sesiones atípicas."
                : "Peso de trabajo: el más usado en las series efectivas de la sesión. Puntos grises: sesiones atípicas (no cuentan para tendencias)."
        case .amount:
            return measurement == .duration ? "Segundos totales en las series de trabajo de cada sesión." : "Repeticiones totales en las series de trabajo de cada sesión."
        }
    }

    private func amountText(_ p: ExercisePoint) -> String {
        p.measurement == .duration ? "\(p.totalAmount) s" : "\(p.totalAmount) reps"
    }

    private func value(_ p: ExercisePoint) -> Double? {
        let fmt = model.loadFormatter
        switch metric {
        case .load: return fmt.value(p.workingLoad)
        case .amount: return Double(p.totalAmount)
        case .oneRepMax: return p.estimatedOneRepMax.map(fmt.value)
        case .volume: return p.measurement == .duration ? Double(p.totalAmount) : fmt.value(p.volume)
        }
    }
}

/// Direct and indirect sets per muscle in the period, with optional user-set weekly goals.
struct MuscleVolumeView: View {
    @Environment(AppModel.self) private var model
    let interval: DateInterval
    let title: String
    var routineId: UUID?
    @State private var editingGoal: MuscleGroup?

    var body: some View {
        let _ = model.revision
        let settings = model.settings
        let volume = model.stats.muscleVolume(in: interval, routineId: routineId).sorted { $0.directSets > $1.directSets }
        let weeks = max(1.0, Double(model.stats.calendar.daysBetween(interval.start, interval.end)) / 7)
        List {
            Section {
                ForEach(volume, id: \.muscle) { item in
                    NavigationLink { MuscleWeeklyView(muscle: item.muscle) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.muscle.label)
                                if let goal = settings.weeklySetGoal(for: item.muscle) {
                                    Text("Tu objetivo: \(goal) series directas por semana")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(item.directSets) directas").font(.subheadline.monospacedDigit())
                                Text("\(GymFormat.number(item.indirectSets, maxFractionDigits: 1)) indirectas · \(GymFormat.number(Double(item.frequencyDays) / weeks, maxFractionDigits: 1)) días/sem.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button { editingGoal = item.muscle } label: { Label("Objetivo", systemImage: "target") }
                            .tint(Theme.accent)
                    }
                }
                if volume.isEmpty { Text("Sin series en este período.").foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text(title)
                    HelpButton(title: "Series indirectas", text: MetricHelp.indirect)
                }
            } footer: {
                Text("Los objetivos de series semanales son tuyos (deslizá un músculo para definirlo): la app no impone una cantidad ideal.")
            }
        }
        .navigationTitle("Grupos musculares")
        .sheet(item: Binding(get: { editingGoal.map(MuscleGoalTarget.init) }, set: { editingGoal = $0?.muscle })) { target in
            NavigationStack { MuscleGoalEditor(muscle: target.muscle) }
                .presentationDetents([.medium])
        }
    }
}

private struct MuscleGoalTarget: Identifiable {
    let muscle: MuscleGroup
    var id: String { muscle.rawValue }
}

private struct MuscleGoalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let muscle: MuscleGroup
    @State private var hasGoal = false
    @State private var sets = 10

    var body: some View {
        Form {
            Toggle("Objetivo semanal", isOn: $hasGoal)
            if hasGoal {
                Stepper("\(sets) series directas por semana", value: $sets, in: 1...40)
            }
        }
        .navigationTitle(muscle.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    var updated = model.settings
                    updated.setWeeklySetGoal(hasGoal ? sets : nil, for: muscle)
                    if model.perform({ try model.repository.saveSettings(updated) }) != nil { dismiss() }
                }
            }
        }
        .onAppear {
            let goal = model.settings.weeklySetGoal(for: muscle)
            hasGoal = goal != nil
            sets = goal ?? 10
        }
    }
}

private struct MuscleWeeklyView: View {
    @Environment(AppModel.self) private var model
    let muscle: MuscleGroup

    var body: some View {
        let _ = model.revision
        let weeks = model.stats.weeklyDirectSets(muscle: muscle, weeks: 12, now: model.now())
        let goal = model.settings.weeklySetGoal(for: muscle)
        List {
            Chart {
                ForEach(weeks, id: \.weekStart) { week in
                    BarMark(x: .value("Semana", week.weekStart, unit: .weekOfYear), y: .value("Series", Double(week.directSets)))
                        .foregroundStyle(by: .value("Tipo", "Directas"))
                    BarMark(x: .value("Semana", week.weekStart, unit: .weekOfYear), y: .value("Series", week.indirectSets))
                        .foregroundStyle(by: .value("Tipo", "Indirectas (estimadas)"))
                }
                if let goal {
                    RuleMark(y: .value("Objetivo", Double(goal)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartForegroundStyleScale(["Directas": Theme.accent, "Indirectas (estimadas)": Theme.accent.opacity(0.35)])
            .frame(height: 220)
            .accessibilityLabel("Series semanales de \(muscle.label), últimas 12 semanas")
            Text("Barras apiladas: directas e indirectas estimadas se informan por separado.\(goal.map { " Línea punteada: tu objetivo de \($0) series directas." } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(muscle.label)
    }
}
