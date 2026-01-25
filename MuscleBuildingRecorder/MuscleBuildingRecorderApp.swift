//
//  MuscleBuildingRecorderApp.swift
//  MuscleBuildingRecorder
//
//  Created by kiichi yokokawa on 2025/10/01.
//

import SwiftUI
import CoreData
import WatchConnectivity
import WidgetKit

@main
struct MuscleBuildingRecorderApp: App {
    // AdMob SDK初期化用AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // ScenePhaseを監視してアプリのアクティブ状態を検知
    @Environment(\.scenePhase) private var scenePhase

    let dataController = DataController.shared
    @StateObject private var heartRateManager = HeartRateManager.shared
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @StateObject private var watchConnectivity = WatchConnectivityService.shared
    @StateObject private var proUserManager = ProUserManager.shared

    // AdMob初期化が完了したかどうか
    @State private var hasRequestedTracking = false

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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                if !hasRequestedTracking {
                    // アプリがアクティブになった時にATT/AdMobを初期化
                    print("iPhone App: 📱 Scene became active, requesting tracking authorization...")
                    hasRequestedTracking = true
                    appDelegate.requestTrackingAuthorization()
                }
                // Widgetからのpendingコマンドを処理
                handlePendingWidgetCommands()

                // 保存されたセッション状態をチェック（初回のみ）
                if !sessionManager.hasPendingSessionRestore && sessionManager.currentPhase == .idle {
                    sessionManager.loadSavedSessionState()
                }

            case .background:
                // バックグラウンドに移行時にセッション状態を保存
                print("iPhone App: 📱 Scene entering background, saving session state...")
                sessionManager.saveSessionState()

            case .inactive:
                // 非アクティブ時も状態を保存（タスクキルに備えて）
                sessionManager.saveSessionState()

            @unknown default:
                break
            }
        }
    }

    // MARK: - Widget Commands Handling

    /// App Groupに保存されたpendingコマンドを処理
    private func handlePendingWidgetCommands() {
        guard let userDefaults = UserDefaults(suiteName: "group.yokAppDev.MuscleBuildingRecorder") else { return }

        // フェーズ切り替え
        if userDefaults.bool(forKey: "pendingPhaseToggle") {
            userDefaults.set(false, forKey: "pendingPhaseToggle")
            print("iPhone App: 📱 Handling pendingPhaseToggle from Widget")
            sessionManager.togglePhase()
        }

        // ワークアウト開始
        if userDefaults.bool(forKey: "pendingStartWorkout") {
            userDefaults.set(false, forKey: "pendingStartWorkout")
            print("iPhone App: 📱 Handling pendingStartWorkout from Widget")
            if sessionManager.currentPhase == .idle {
                sessionManager.startSession()
            }
        }

        // ワークアウト終了
        if userDefaults.bool(forKey: "pendingEndWorkout") {
            userDefaults.set(false, forKey: "pendingEndWorkout")
            print("iPhone App: 📱 Handling pendingEndWorkout from Widget")
            if sessionManager.currentPhase != .idle {
                sessionManager.endSession()
            }
        }

        userDefaults.synchronize()
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
