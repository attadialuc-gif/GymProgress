import GymCore
import GymStore
import SwiftUI

/// Five-tab navigation. On launch, an interrupted session (active/paused) is offered for resuming.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var offeredResume = false
    @State private var showResume = false

    var body: some View {
        if let storeError = model.storeError {
            ContentUnavailableView {
                Label("No se pudieron abrir tus datos", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(storeError)
            }
            .preferredColorScheme(.dark)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        @Bindable var model = model
        let _ = model.revision
        return TabView(selection: $model.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Inicio", systemImage: "house") }
                .tag(AppTab.home)
            NavigationStack { RoutinesView() }
                .tabItem { Label("Rutinas", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.routines)
            NavigationStack(path: $model.workoutPath) { WorkoutTabView() }
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
            updateScreenAwake()
            guard !offeredResume else { return }
            offeredResume = true
            showResume = model.workout.openSession() != nil
        }
        // Keep the screen on for the whole open session (any screen of the app), never otherwise.
        .onChange(of: model.revision) { _, _ in updateScreenAwake() }
        .onChange(of: scenePhase) { _, _ in updateScreenAwake() }
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

    private func updateScreenAwake() {
        let on = scenePhase == .active && model.settings.keepScreenOn && model.workout.openSession() != nil
        ScreenAwake.set(on)
    }
}
