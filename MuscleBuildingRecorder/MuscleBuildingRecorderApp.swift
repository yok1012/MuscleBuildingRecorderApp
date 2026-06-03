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
    @StateObject private var localizationManager = LocalizationManager.shared

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
                .environmentObject(localizationManager)
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .environment(\.locale, localizationManager.locale)
                .id(localizationManager.language)
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
                // 保存されたセッション状態をチェック（初回のみ）
                if !sessionManager.hasPendingSessionRestore && sessionManager.currentPhase == .idle {
                    sessionManager.loadSavedSessionState()
                }

                // スクリーンタイム制限の整合性チェック
                // （セッション idle なのに shield が残っている矛盾状態を強制解除）
                if #available(iOS 16.0, *) {
                    ScreenTimeManager.shared.refreshAuthorizationStatus()
                    ScreenTimeManager.shared.safetyCheckIfIdle(
                        sessionActive: sessionManager.currentPhase != .idle
                    )
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

    private func setupApp() {
        print("iPhone App: 🚀 Starting app setup...")

        // スクリーンタイム制限の起動時 safety check
        // （前回起動時に shield を張ったままクラッシュした等の場合、ここでクリアする）
        if #available(iOS 16.0, *) {
            ScreenTimeManager.shared.refreshAuthorizationStatus()
            ScreenTimeManager.shared.safetyCheckIfIdle(
                sessionActive: sessionManager.currentPhase != .idle
            )
        }

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
