//
//  MuscleBuildingRecorderApp.swift
//  MuscleBuildingRecorder
//
//  Created by kiichi yokokawa on 2025/10/01.
//

import SwiftUI
import CoreData
import WatchConnectivity

@main
struct MuscleBuildingRecorderApp: App {
    let dataController = DataController.shared
    @StateObject private var heartRateManager = HeartRateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartRateManager)
                .environmentObject(sessionManager)
                .environmentObject(sensorLogManager)
                .environmentObject(watchConnectivity)
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        print("iPhone App: 🚀 Starting app setup...")

        // WatchConnectivityの初期化（重要！）
        _ = WatchConnectivityService.shared
        print("iPhone App: ✅ WatchConnectivityService initialized")

        // SessionManagerの初期化
        _ = SessionManager.shared
        print("iPhone App: ✅ SessionManager initialized")

        heartRateManager.requestAuthorization()
        dataController.loadInitialData()

        // センサーログマネージャーの初期化
        sensorLogManager.startSessionIfNeeded()
        print("iPhone App: ✅ SensorLogManager initialized")
    }
}
