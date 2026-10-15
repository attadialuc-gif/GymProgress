import GymCore
import GymStore
import SwiftUI

struct RoutinesView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var showNew = false
    @State private var showArchived = false
    @State private var pendingDelete: RoutineTemplate?

    var body: some View {
        let _ = model.revision
        let all = model.repository.routines()
        let active = all.filter { !$0.isArchived }
        let archived = all.filter(\.isArchived)

        List {
            if active.isEmpty {
                ContentUnavailableView(
                    "Sin rutinas",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Creá una rutina vacía o partí de una plantilla editable.")
                )
            }
            Section {
                ForEach(active) { routine in
                    NavigationLink(value: routine.id) {
                        RoutineRow(routine: routine)
                    }
                    .swipeActions(edge: .trailing) {
                        Button { pendingDelete = routine } label: { Label("Eliminar", systemImage: "trash") }
                            .tint(.red)
                        Button { model.perform { try model.routines.setArchived(routineId: routine.id, true) } } label: {
                            Label("Archivar", systemImage: "archivebox")
                        }
                        .tint(.gray)
                    }
                    .swipeActions(edge: .leading) {
                        Button { model.perform { try model.routines.duplicateRoutine(id: routine.id, now: model.now()) } } label: {
                            Label("Duplicar", systemImage: "plus.square.on.square")
                        }
                        .tint(Theme.accent)
                    }
                }
                .onMove { from, to in
                    var ids = active.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.perform { try model.routines.reorderRoutines(ids) }
                }
            }
            if !archived.isEmpty {
                Section {
                    DisclosureGroup("Archivadas (\(archived.count))", isExpanded: $showArchived) {
                        ForEach(archived) { routine in
                            HStack {
                                Text(routine.name).foregroundStyle(.secondary)
                                Spacer()
                                Button("Restaurar") { model.perform { try model.routines.setArchived(routineId: routine.id, false) } }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Rutinas")
        .navigationDestination(for: UUID.self) { id in
            RoutineDetailView(routineId: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { LibraryView() } label: { Label("Biblioteca", systemImage: "books.vertical") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newName = ""; showNew = true } label: { Label("Rutina vacía", systemImage: "plus") }
                    Section("Plantillas editables") {
                        ForEach(RoutinePreset.all) { preset in
                            Button(preset.name) {
                                model.perform { try model.routines.createFromPreset(preset, now: model.now()) }
                            }
                        }
                    }
                } label: {
                    Label("Nueva rutina", systemImage: "plus")
                }
            }
        }
        .alert("Nueva rutina", isPresented: $showNew) {
            TextField("Nombre", text: $newName)
            Button("Crear") { model.perform { try model.routines.createRoutine(name: newName, now: model.now()) } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar la rutina?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { routine in
            if model.repository.hasHistory(routineId: routine.id) {
                Button("Archivar (tiene historial)") { model.perform { try model.routines.setArchived(routineId: routine.id, true) } }
            } else {
                Button("Eliminar", role: .destructive) { model.perform { try model.routines.deleteRoutine(id: routine.id) } }
            }
        } message: { routine in
            Text(model.repository.hasHistory(routineId: routine.id)
                 ? "\"\(routine.name)\" tiene entrenamientos registrados: se archiva y el historial queda intacto."
                 : "\"\(routine.name)\" no tiene historial y se eliminará.")
        }
    }
}

private struct RoutineRow: View {
    @Environment(AppModel.self) private var model
    let routine: RoutineTemplate

    var body: some View {
        let items = model.repository.routineExercises(routineId: routine.id)
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name).font(.headline)
            Text(items.isEmpty ? "Sin ejercicios" : "\(items.count) ejercicios")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
