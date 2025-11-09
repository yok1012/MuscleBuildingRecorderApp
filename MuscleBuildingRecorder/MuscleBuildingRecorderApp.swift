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

        // WatchConnectivityの初期化（重要！最初に実行）
        let watchService = WatchConnectivityService.shared
        print("iPhone App: ✅ WatchConnectivityService initialized: \(watchService)")

        // SessionManagerの初期化
        let sessionMgr = SessionManager.shared
        print("iPhone App: ✅ SessionManager initialized: \(sessionMgr)")

        heartRateManager.requestAuthorization()
        dataController.loadInitialData()

        // センサーログマネージャーの初期化
        sensorLogManager.startSessionIfNeeded()
        print("iPhone App: ✅ SensorLogManager initialized")

        // 初期化状態を確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("iPhone App: 🔍 Checking WCSession state...")
            print("iPhone App: WCSession is supported: \(WCSession.isSupported())")
            if WCSession.isSupported() {
                let session = WCSession.default
                print("iPhone App: WCSession delegate: \(String(describing: session.delegate))")
                print("iPhone App: WCSession activation state: \(session.activationState.rawValue)")
                print("iPhone App: Is reachable: \(session.isReachable)")
            }
        }
    }
}
