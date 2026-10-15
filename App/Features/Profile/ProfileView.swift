import GymCore
import GymStore
import SwiftUI
import UniformTypeIdentifiers

/// Profile and settings (section 9.7), export / import / backup (section 12).
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var csvURL: URL?
    @State private var showImporter = false
    @State private var importResult: String?
    @State private var bodyweightText = ""

    var body: some View {
        let _ = model.revision
        let settings = model.settings
        Form {
            Section("Preferencias") {
                Picker("Unidad de peso", selection: binding(\.weightUnit, settings)) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                Picker("La semana empieza", selection: binding(\.firstWeekday, settings)) {
                    Text("Lunes").tag(2)
                    Text("Domingo").tag(1)
                }
                Stepper("Descanso por defecto: \(settings.defaultRestSeconds) s", value: binding(\.defaultRestSeconds, settings), in: 15...600, step: 15)
                Picker("Tema", selection: binding(\.theme, settings)) {
                    Text("Oscuro").tag(AppTheme.dark)
                    Text("Claro").tag(AppTheme.light)
                    Text("Sistema").tag(AppTheme.system)
                }
                Toggle("Mantener pantalla encendida en sesión", isOn: binding(\.keepScreenOn, settings))
                Toggle("Aviso al terminar el descanso", isOn: binding(\.restNotifications, settings))
            }

            Section {
                Stepper("Objetivo semanal: \(settings.weeklyGoal) entrenamientos", value: binding(\.weeklyGoal, settings), in: 1...14)
                Picker("Racha", selection: binding(\.streakMode, settings)) {
                    Text("Por cumplimiento del plan").tag(StreakMode.weeklyPlan)
                    Text("Por días de entrenamiento").tag(StreakMode.dayGap)
                }
                if settings.streakMode == .dayGap {
                    Stepper("Máximo entre entrenamientos: \(settings.maxGapDays) días", value: binding(\.maxGapDays, settings), in: 1...7)
                }
                Stepper("Sesión válida: ≥ \(settings.minSetsForValidSession) series efectivas", value: binding(\.minSetsForValidSession, settings), in: 1...20)
            } header: {
                Text("Constancia")
            } footer: {
                Text(model.consistency.streak(now: model.now()).definition)
            }

            Section {
                Picker("Fórmula de 1RM", selection: oneRepMaxFormula(settings)) {
                    Text("Epley").tag(OneRepMaxFormula.epley)
                    Text("Brzycki").tag(OneRepMaxFormula.brzycki)
                }
                Stepper("Usar series de hasta \(settings.oneRepMax.maxReps) reps", value: oneRepMaxCap(settings), in: 1...20)
                Stepper("Factor de series indirectas: \(GymFormat.number(settings.indirectSetFactor))", value: binding(\.indirectSetFactor, settings), in: 0...1, step: 0.1)
                LabeledContent("Peso corporal (\(settings.weightUnit.rawValue))") {
                    TextField("Opcional", text: $bodyweightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(saveBodyweight)
                }
            } header: {
                Text("Cálculos")
            } footer: {
                Text("El 1RM es siempre una estimación. El peso corporal solo se usa para el volumen de ejercicios con peso corporal; si no lo cargás, se cuenta solo la carga externa.")
            }

            Section {
                Button("Exportar copia completa (JSON)") { exportURL = writeExport() }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Compartir copia JSON", systemImage: "square.and.arrow.up") }
                }
                Button("Exportar series (CSV)") { csvURL = writeCSV() }
                if let csvURL {
                    ShareLink(item: csvURL) { Label("Compartir CSV", systemImage: "tablecells") }
                }
                Button("Importar / restaurar copia…") { showImporter = true }
            } header: {
                Text("Datos y copias de seguridad")
            } footer: {
                Text("Tus datos viven solo en este iPhone. La copia incluye entrenamientos, decisiones sobre recomendaciones y vínculos de equivalencia. Importar solo agrega lo que no existe: nunca reemplaza ni borra lo que ya tenés.")
            }

            Section("Acerca de") {
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("Las recomendaciones son orientativas, se basan solo en tus registros y no constituyen consejo médico. Sin conexión, sin cuentas y sin analíticas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Perfil")
        .onAppear { bodyweightText = model.loadFormatter.editable(settings.bodyweightKg) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importFile(result)
        }
        .alert("Importación", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResult ?? "")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<UserSettings, T>, _ settings: UserSettings) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = model.settings
                updated[keyPath: keyPath] = value
                model.perform { try model.repository.saveSettings(updated) }
            }
        )
    }

    private func oneRepMaxFormula(_ settings: UserSettings) -> Binding<OneRepMaxFormula> {
        Binding(
            get: { settings.oneRepMax.formula },
            set: { value in
                var updated = model.settings
                updated.oneRepMax.formula = value
                model.perform { try model.repository.saveSettings(updated) }
            }
        )
    }

    private func oneRepMaxCap(_ settings: UserSettings) -> Binding<Int> {
        Binding(
            get: { settings.oneRepMax.maxReps },
            set: { value in
                var updated = model.settings
                updated.oneRepMax.maxReps = value
                model.perform { try model.repository.saveSettings(updated) }
            }
        )
    }

    private func saveBodyweight() {
        var updated = model.settings
        updated.bodyweightKg = bodyweightText.isEmpty ? nil : model.loadFormatter.parse(bodyweightText)
        model.perform { try model.repository.saveSettings(updated) }
    }

    private func stamp() -> String {
        model.now().formatted(.iso8601.year().month().day())
    }

    private func writeExport() -> URL? {
        model.perform {
            let data = try model.exporter.exportJSON(now: model.now())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("GymProgress-\(stamp()).json")
            try data.write(to: url, options: .atomic)
            return url
        } ?? nil
    }

    private func writeCSV() -> URL? {
        model.perform {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("GymProgress-series-\(stamp()).csv")
            try Data(model.exporter.exportSetsCSV().utf8).write(to: url, options: .atomic)
            return url
        } ?? nil
    }

    private func importFile(_ result: Result<URL, Error>) {
        switch result {
        case let .failure(error):
            importResult = error.localizedDescription
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importResult = "No se pudo leer el archivo."
                return
            }
            if let summary = model.perform({ try model.exporter.importJSON(data) }) {
                var text = "Se agregaron \(summary.inserted) registros. \(summary.unchanged) ya estaban."
                if summary.conflicts > 0 {
                    text += " \(summary.conflicts) registros del archivo eran distintos a los tuyos: se conservaron los tuyos."
                }
                importResult = text
            }
        }
    }
}
