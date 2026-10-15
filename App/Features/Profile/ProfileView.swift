import GymCore
import GymStore
import SwiftUI

/// Settings (stage 3 scope: units, week start, rest, theme, screen, export). Completed in stage 7.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?

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
                Button("Exportar copia (JSON)") { exportURL = writeExport() }
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Compartir copia", systemImage: "square.and.arrow.up") }
                }
            } header: {
                Text("Datos")
            } footer: {
                Text("Tus datos viven solo en este iPhone. La copia incluye entrenamientos, decisiones sobre recomendaciones y vínculos de equivalencia.")
            }

            Section("Acerca de") {
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("Las recomendaciones son orientativas, se basan solo en tus registros y no constituyen consejo médico. El 1RM es siempre una estimación.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Perfil")
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

    private func writeExport() -> URL? {
        model.perform {
            let data = try model.exporter.exportJSON(now: model.now())
            let name = "GymProgress-\(model.now().formatted(.iso8601.year().month().day())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } ?? nil
    }
}
