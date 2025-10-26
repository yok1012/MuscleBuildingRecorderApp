//
//  MuscleBuildingRecorderApp.swift
//  MuscleBuildingRecorder
//
//  Created by kiichi yokokawa on 2025/10/01.
//

import SwiftUI
import CoreData

@main
struct MuscleBuildingRecorderApp: App {
    let dataController = DataController.shared
    @StateObject private var heartRateManager = HeartRateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var sensorLogManager = SensorLogManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartRateManager)
                .environmentObject(sessionManager)
                .environmentObject(sensorLogManager)
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        heartRateManager.requestAuthorization()
        dataController.loadInitialData()

        // センサーログマネージャーの初期化
        sensorLogManager.startSessionIfNeeded()
    }
}
