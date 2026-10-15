import GymCore
import GymStore
import SwiftUI

/// Five-tab navigation. On launch, an interrupted session (active/paused) is offered for resuming.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var offeredResume = false
    @State private var showResume = false

    var body: some View {
        @Bindable var model = model
        let _ = model.revision
        TabView(selection: $model.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Inicio", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { RoutinesView() }
                .tabItem { Label("Rutinas", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.routines)
            NavigationStack { WorkoutTabView() }
                .tabItem { Label("Entrenar", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.workout)
            NavigationStack { ProgressHomeView() }
                .tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .preferredColorScheme(Theme.colorScheme(for: model.settings.theme))
        .onAppear {
            guard !offeredResume else { return }
            offeredResume = true
            showResume = model.workout.openSession() != nil
        }
        .alert("Tenés un entrenamiento en curso", isPresented: $showResume) {
            Button("Retomar") { model.selectedTab = .workout }
            Button("Más tarde", role: .cancel) {}
        } message: {
            Text("Se guardó todo lo que registraste, incluidas tus decisiones sobre las recomendaciones.")
        }
        .alert("Atención", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
