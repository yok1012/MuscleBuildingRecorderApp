import SwiftUI

@main
struct WorkoutTimerApp: App {
    @StateObject private var dataController = DataController.shared
    @StateObject private var heartRateManager = HeartRateManager.shared
    @StateObject private var sessionManager = SessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataController)
                .environmentObject(heartRateManager)
                .environmentObject(sessionManager)
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        heartRateManager.requestAuthorization()
        dataController.loadInitialData()
    }
}