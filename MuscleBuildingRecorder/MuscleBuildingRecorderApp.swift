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
    // AdMob SDK初期化用AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let dataController = DataController.shared
    @StateObject private var heartRateManager = HeartRateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    @StateObject private var proUserManager = ProUserManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(heartRateManager)
                .environmentObject(sessionManager)
                .environmentObject(sensorLogManager)
                .environmentObject(watchConnectivity)
                .environmentObject(proUserManager)
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

        // 心拍数監視を自動開始（Watchアプリなしでも心拍数取得可能に）
        // 認可完了後に開始するため少し遅延させる
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("iPhone App: 💓 Starting automatic heart rate monitoring...")
            heartRateManager.startMonitoring()
        }

        // 注意: SensorLogManagerはWCSessionDelegateを実装しなくなりました
        // WatchConnectivityServiceが唯一のデリゲートとして動作し、
        // センサーデータをSensorLogManagerに転送します
        print("iPhone App: ✅ SensorLogManager initialized (receives data from WatchConnectivityService)")

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
