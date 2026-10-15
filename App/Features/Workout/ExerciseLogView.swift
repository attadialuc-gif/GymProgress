import GymCore
import GymStore
import SwiftUI

/// Exercise screen during a session: recommendation card first, then the set table.
struct ExerciseLogView: View {
    @Environment(AppModel.self) private var model
    let logId: UUID

    @State private var state: ExerciseLogState?
    @State private var showModify = false
    @State private var savingInitialTarget = false
    @State private var showContext = false
    @State private var completedTick = 0
    @State private var notesDraft = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        let _ = model.revision
        Group {
            if let state = currentState() {
                content(state)
            } else {
                ProgressView()
            }
        }
        .task(id: logId) {
            // Opening freezes the recommendation (computed with history prior to this session).
            state = model.perform { try model.workout.openExercise(logId: logId, now: model.now()) }
        }
        .sensoryFeedback(.success, trigger: completedTick)
    }

    /// Re-reads sets/decision after each mutation; the recommendation itself stays frozen.
    private func currentState() -> ExerciseLogState? {
        guard let state, let log = model.repository.exerciseLog(id: logId) else { return nil }
        return ExerciseLogState(
            log: log,
            sets: model.repository.setLogs(exerciseLogId: logId),
            recommendation: log.frozenRecommendation ?? state.recommendation,
            decision: model.repository.decision(exerciseLogId: logId)
        )
    }

    @ViewBuilder
    private func content(_ state: ExerciseLogState) -> some View {
        let fmt = model.loadFormatter
        let log = state.log
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecommendationCard(
                    recommendation: state.recommendation,
                    decision: state.decision,
                    formatter: fmt,
                    onAccept: { model.perform { try model.workout.decide(logId: logId, choice: .accept, now: model.now()) } },
                    onModify: { savingInitialTarget = false; showModify = true },
                    onIgnore: { model.perform { try model.workout.decide(logId: logId, choice: .ignore, now: model.now()) } },
                    onCopyPrevious: { nonEquivalent in
                        model.perform { try model.workout.copyPreviousLoads(logId: logId, allowNonEquivalent: nonEquivalent, now: model.now()) }
                    },
                    onSetInitialTarget: { savingInitialTarget = true; showModify = true }
                )

                contextRow(log)

                SetTable(log: log, sets: state.sets, previous: state.recommendation.lastPerformance) { set in
                    if model.perform({ try model.workout.completeSet(setId: set.id, now: model.now()) }) != nil {
                        completedTick += 1
                        let rest = log.restSeconds ?? model.settings.defaultRestSeconds
                        model.restTimer.start(seconds: rest, now: model.now(), notify: model.settings.restNotifications)
                    }
                }

                RestTimerBanner()

                HStack {
                    Button { model.perform { try model.workout.addSet(logId: logId) } } label: {
                        Label("Serie", systemImage: "plus")
                    }
                    Button { model.perform { try model.workout.addSet(logId: logId, kind: .warmup) } } label: {
                        Label("Calentamiento", systemImage: "flame")
                    }
                }
                .buttonStyle(.bordered)

                Toggle("Ejercicio atípico hoy", isOn: Binding(
                    get: { log.isAtypical },
                    set: { value in model.perform { try model.workout.setExerciseAtypical(logId: logId, value) } }
                ))
                TextField("Notas del ejercicio", text: $notesDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($notesFocused)
                    .onAppear { notesDraft = log.notes }
                    .onDisappear {
                        if notesDraft != log.notes {
                            model.perform { try model.workout.setExerciseNotes(logId: logId, notes: notesDraft) }
                        }
                    }
                    // Saved when editing ends (not on every keystroke).
                    .onChange(of: notesFocused) { _, focused in
                        if !focused, notesDraft != log.notes {
                            model.perform { try model.workout.setExerciseNotes(logId: logId, notes: notesDraft) }
                        }
                    }
            }
            .padding()
        }
        .navigationTitle(log.snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModify) {
            NavigationStack {
                ModifyRecommendationSheet(
                    recommendation: state.recommendation,
                    increment: log.configSnapshot.increment,
                    formatter: fmt,
                    title: savingInitialTarget ? "Objetivo inicial" : "Modificar objetivo"
                ) { weight, reps, seconds in
                    if savingInitialTarget {
                        model.perform { try model.workout.setInitialTarget(logId: logId, weight: weight, reps: reps, seconds: seconds, now: model.now()) }
                    } else {
                        model.perform { try model.workout.decide(logId: logId, choice: .modify(weight: weight, reps: reps, seconds: seconds), now: model.now()) }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showContext) {
            NavigationStack { ContextEditor(log: log) }
                .presentationDetents([.medium])
        }
    }

    private func contextRow(_ log: ExerciseLog) -> some View {
        Button { showContext = true } label: {
            HStack {
                Image(systemName: "slider.horizontal.3")
                Text([log.equipmentLabel, log.variantLabel].compactMap { $0 }.joined(separator: " · ").isEmpty
                     ? "Máquina / variante: estándar"
                     : [log.equipmentLabel, log.variantLabel].compactMap { $0 }.joined(separator: " · "))
                Spacer()
                Text("Cambiar").foregroundStyle(Theme.accent)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Indicá si hoy usás otra máquina o variante: no se compara con otro contexto")
    }
}

/// Change of machine / variant (comparability context, section 8.1).
private struct ContextEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let log: ExerciseLog
    @State private var equipment = ""
    @State private var variant = ""

    private var currentLabel: String {
        let parts = [log.equipmentLabel, log.variantLabel].compactMap { $0 }
        return parts.isEmpty ? "estándar" : parts.joined(separator: " · ")
    }

    var body: some View {
        Form {
            Section {
                TextField("Máquina / equipo (ej.: Polea 2)", text: $equipment)
                TextField("Variante (ej.: agarre cerrado)", text: $variant)
            } footer: {
                Text("Con otro contexto la app no compara automáticamente con el historial anterior. Si son equivalentes, podés vincularlos.")
            }
            Section {
                Button("Guardar y tratar como equivalente al anterior") {
                    model.perform {
                        try model.workout.switchContextTreatingAsEquivalent(logId: log.id, variantLabel: variant, equipmentLabel: equipment, now: model.now())
                    }
                    dismiss()
                }
            } footer: {
                Text("Vincula el contexto que estabas usando (\(currentLabel)) con el nuevo: desde ahora sus resultados se comparan entre sí.")
            }
        }
        .navigationTitle("Contexto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    model.perform { try model.workout.setContext(logId: log.id, variantLabel: variant, equipmentLabel: equipment, now: model.now()) }
                    dismiss()
                }
            }
        }
        .onAppear {
            equipment = log.equipmentLabel ?? ""
            variant = log.variantLabel ?? ""
        }
    }
}
