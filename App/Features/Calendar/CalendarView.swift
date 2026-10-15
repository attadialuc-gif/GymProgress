import GymCore
import GymStore
import SwiftUI

/// Monthly / weekly calendar: completed, planned, missed and rest days (section 9.5).
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var anchor = Date()
    @State private var weekly = false
    @State private var showPlan = false

    var body: some View {
        let _ = model.revision
        let now = model.now()
        let days = weekly ? model.consistency.week(containing: anchor, now: now) : model.consistency.month(containing: anchor, now: now)
        let cal = model.consistency.calendar

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Vista", selection: $weekly) {
                    Text("Mes").tag(false)
                    Text("Semana").tag(true)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Anterior")
                    Spacer()
                    Text(title(cal: cal)).font(.headline)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Siguiente")
                }

                weekdayHeader(cal: cal)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<leadingBlanks(days: days, cal: cal), id: \.self) { _ in Color.clear.frame(height: 44) }
                    ForEach(days) { day in
                        DayCell(day: day, dayNumber: cal.calendar.component(.day, from: day.date))
                    }
                }

                legend

                Card {
                    let plan = model.consistency.plan(asOf: now)
                    Text("Plan semanal vigente").font(.headline)
                    if plan.isEmpty {
                        Text("Sin días planificados.").foregroundStyle(.secondary)
                    }
                    ForEach(orderedWeekdays(cal: cal), id: \.self) { weekday in
                        if let routineId = plan[weekday], let routine = model.repository.routine(id: routineId) {
                            LabeledContent(weekdayName(weekday, cal: cal), value: routine.name)
                        }
                    }
                    Button("Editar plan") { showPlan = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Calendario")
        .sheet(isPresented: $showPlan) {
            NavigationStack { WeeklyPlanEditor() }
        }
    }

    private func move(_ step: Int) {
        let cal = model.consistency.calendar.calendar
        anchor = cal.date(byAdding: weekly ? .weekOfYear : .month, value: step, to: anchor) ?? anchor
    }

    private func title(cal: TrainingCalendar) -> String {
        if weekly {
            let start = cal.weekStart(of: anchor)
            return "Semana del \(start.formatted(.dateTime.day().month(.wide)))"
        }
        return anchor.formatted(.dateTime.month(.wide).year())
    }

    private func leadingBlanks(days: [CalendarDay], cal: TrainingCalendar) -> Int {
        guard !weekly, let first = days.first else { return 0 }
        return (cal.weekday(of: first.date) - cal.calendar.firstWeekday + 7) % 7
    }

    private func orderedWeekdays(cal: TrainingCalendar) -> [Int] {
        (0..<7).map { (cal.calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func weekdayName(_ weekday: Int, cal: TrainingCalendar) -> String {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_AR")
        return c.weekdaySymbols[weekday - 1].capitalized
    }

    private func weekdayHeader(cal: TrainingCalendar) -> some View {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_AR")
        let symbols = c.veryShortWeekdaySymbols
        return HStack {
            ForEach(orderedWeekdays(cal: cal), id: \.self) { weekday in
                Text(symbols[weekday - 1]).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendDot(color: Theme.accent, text: "Hecho")
            LegendDot(color: .blue, text: "Planificado")
            LegendDot(color: Theme.caution, text: "Omitido")
            LegendDot(color: .gray.opacity(0.4), text: "Descanso")
        }
        .font(.caption)
    }
}

private struct DayCell: View {
    let day: CalendarDay
    let dayNumber: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(dayNumber)")
                .font(.subheadline.weight(day.isToday ? .bold : .regular))
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(day.isToday ? Theme.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)): \(statusText)")
    }

    private var color: Color {
        switch day.status {
        case .completed: Theme.accent
        case .planned: .blue
        case .missed: Theme.caution
        case .rest: .gray.opacity(0.4)
        }
    }

    private var statusText: String {
        switch day.status {
        case .completed: "entrenamiento hecho"
        case .planned: "planificado\(day.plannedRoutineName.map { ": \($0)" } ?? "")"
        case .missed: "planificado y omitido"
        case .rest: "descanso"
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

/// Choose training days and the routine for each. Changes apply from the chosen date; the past
/// keeps the plan it had (validFrom).
struct WeeklyPlanEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var assignments: [Int: UUID] = [:]
    @State private var from = Date()
    @State private var loaded = false

    var body: some View {
        let routines = model.repository.routines().filter { !$0.isArchived }
        let cal = model.consistency.calendar
        Form {
            Section {
                ForEach((0..<7).map { (cal.calendar.firstWeekday - 1 + $0) % 7 + 1 }, id: \.self) { weekday in
                    Picker(weekdayName(weekday), selection: Binding(
                        get: { assignments[weekday] },
                        set: { assignments[weekday] = $0 }
                    )) {
                        Text("Descanso").tag(UUID?.none)
                        ForEach(routines) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            } footer: {
                Text("\(assignments.count) días por semana.")
            }
            Section {
                DatePicker("Vigente desde", selection: $from, displayedComponents: .date)
            } footer: {
                Text("Los días anteriores conservan el plan que tenían: el historial de planificados y omitidos no cambia.")
            }
        }
        .navigationTitle("Plan semanal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    if model.perform({ try model.consistency.setWeeklyPlan(assignments, from: from, now: model.now()) }) != nil {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            from = model.now()
            assignments = model.consistency.plan(asOf: model.now())
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_AR")
        return c.weekdaySymbols[weekday - 1].capitalized
    }
}
