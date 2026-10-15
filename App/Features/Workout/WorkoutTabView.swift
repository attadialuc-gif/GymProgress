import GymCore
import GymStore
import SwiftUI

/// "Entrenar" tab: the open session, or a quick way to start one.
struct WorkoutTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.revision
        if let session = model.workout.openSession() {
            WorkoutSessionView(sessionId: session.id)
        } else {
            StartWorkoutView()
        }
    }
}

private struct StartWorkoutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let routines = model.repository.routines().filter { !$0.isArchived }
        List {
            Section("Elegí una rutina") {
                if routines.isEmpty {
                    Text("Creá una rutina en la pestaña Rutinas.").foregroundStyle(.secondary)
                }
                ForEach(routines) { routine in
                    Button {
                        model.perform { try model.workout.startSession(routineId: routine.id, now: model.now()) }
                    } label: {
                        Label(routine.name, systemImage: "play.circle")
                    }
                }
            }
            Section {
                Button {
                    model.perform { try model.workout.startSession(routineId: nil, now: model.now()) }
                } label: {
                    Label("Entrenamiento libre", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Entrenar")
    }
}

/// The active session: elapsed time (minus pauses), exercises, pause/finish/discard.
struct WorkoutSessionView: View {
    @Environment(AppModel.self) private var model
    let sessionId: UUID

    @State private var showPicker = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var showNotes = false
    @State private var notes = ""
    @State private var pendingRemoval: UUID?

    var body: some View {
        let _ = model.revision
        if let session = model.repository.session(id: sessionId) {
            content(session)
        }
    }

    @ViewBuilder
    private func content(_ session: WorkoutSession) -> some View {
        let logs = model.repository.exerciseLogs(sessionId: sessionId)
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.routineNameSnapshot ?? "Entrenamiento libre").font(.headline)
                            Text(Duration.seconds(session.elapsed(at: context.date)).formatted(.time(pattern: .hourMinuteSecond)))
                                .font(.system(.title2, design: .rounded).monospacedDigit())
                                .foregroundStyle(session.status == .paused ? .secondary : .primary)
                        }
                        Spacer()
                        if session.status == .paused {
                            Button { model.perform { try model.workout.resume(sessionId: sessionId, now: model.now()) } } label: {
                                Label("Reanudar", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button { model.perform { try model.workout.pause(sessionId: sessionId, now: model.now()) } } label: {
                                Label("Pausar", systemImage: "pause.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                RestTimerBanner()
            }

            Section("Ejercicios") {
                ForEach(logs) { log in
                    NavigationLink(value: log.id) {
                        SessionExerciseRow(log: log)
                    }
                    .swipeActions {
                        Button { pendingRemoval = log.id } label: {
                            Label("Quitar de hoy", systemImage: "minus.circle")
                        }
                        .tint(.red)
                    }
                }
                .onMove { from, to in
                    var ids = logs.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.perform { try model.workout.moveExercises(sessionId: sessionId, orderedLogIds: ids) }
                }
                Button { showPicker = true } label: { Label("Agregar ejercicio (solo hoy)", systemImage: "plus") }
            }

            Section {
                Toggle("Sesión atípica (enfermedad, descarga, viaje)", isOn: Binding(
                    get: { session.isAtypical },
                    set: { value in model.perform { try model.workout.setSessionAtypical(sessionId: sessionId, value, now: model.now()) } }
                ))
                Button { notes = session.notes; showNotes = true } label: {
                    Label(session.notes.isEmpty ? "Agregar nota" : session.notes, systemImage: "note.text")
                }
            } footer: {
                Text("Una sesión atípica se guarda y se muestra, pero no cuenta para tendencias ni recomendaciones.")
            }

            Section {
                Button { confirmFinish = true } label: {
                    Label("Finalizar entrenamiento", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                Button(role: .destructive) { confirmDiscard = true } label: {
                    Label("Descartar entrenamiento", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("En curso")
        .navigationDestination(for: UUID.self) { logId in
            ExerciseLogView(logId: logId)
        }
        .toolbar { EditButton() }
        .confirmationDialog("¿Quitar este ejercicio del entrenamiento de hoy?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            Button("Quitar de hoy", role: .destructive) {
                if let id = pendingRemoval { model.perform { try model.workout.removeExercise(logId: id) } }
                pendingRemoval = nil
            }
        } message: {
            Text("La rutina no cambia. Se pierde lo cargado en este ejercicio hoy (no tiene series completadas).")
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ExercisePickerView { exercise in
                    model.perform { try model.workout.addExercise(sessionId: sessionId, exerciseId: exercise.id, now: model.now()) }
                    showPicker = false
                }
            }
        }
        .alert("Nota de la sesión", isPresented: $showNotes) {
            TextField("Nota", text: $notes)
            Button("Guardar") { model.perform { try model.workout.setSessionNotes(sessionId: sessionId, notes: notes, now: model.now()) } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Finalizar el entrenamiento?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finalizar") {
                model.perform { try model.workout.finish(sessionId: sessionId, now: model.now()) }
                model.restTimer.stop()
                ScreenAwake.set(false)
            }
        } message: {
            Text("Las series pendientes quedan sin realizar (no cuentan como cero).")
        }
        .confirmationDialog("¿Descartar el entrenamiento?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) {
                model.perform { try model.workout.discard(sessionId: sessionId, now: model.now()) }
                model.restTimer.stop()
                ScreenAwake.set(false)
            }
        } message: {
            Text("No contará en el historial, las estadísticas ni las recomendaciones.")
        }
    }
}

private struct SessionExerciseRow: View {
    @Environment(AppModel.self) private var model
    let log: ExerciseLog

    var body: some View {
        let sets = model.repository.setLogs(exerciseLogId: log.id).filter { $0.kind != .warmup }
        let done = sets.filter { $0.status == .completed }.count
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.snapshot.name).font(.headline)
                if let label = [log.variantLabel, log.equipmentLabel].compactMap({ $0 }).first {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(done)/\(sets.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(done == sets.count && done > 0 ? Theme.positive : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.snapshot.name), \(done) de \(sets.count) series completadas")
    }
}

/// Rest countdown from the stored end date (survives lock/background).
struct RestTimerBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.restTimer.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = model.restTimer.remaining(at: context.date)
                HStack {
                    Image(systemName: "timer")
                    Text("Descanso")
                    Spacer()
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Button("+30 s") { model.restTimer.add(seconds: 30, now: context.date, notify: model.settings.restNotifications) }
                        .buttonStyle(.bordered)
                    Button { model.restTimer.stop() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Detener descanso")
                }
                .foregroundStyle(remaining > 0 ? Theme.accent : Theme.positive)
            }
        }
    }
}
