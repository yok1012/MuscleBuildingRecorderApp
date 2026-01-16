//
//  AppDelegate.swift
//  MuscleBuildingRecorder
//
//  AdMob SDK初期化用AppDelegate
//

import UIKit
import AppTrackingTransparency
import AdSupport

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // AdMob SDKの初期化（ATTリクエスト後に行う）
        #if canImport(GoogleMobileAds)
        print("AppDelegate: GoogleMobileAds SDK is available")
        // ATTの許可状態を確認してからAdMobを初期化
        // applicationDidBecomeActiveで実行する
        #else
        print("AppDelegate: ⚠️ GoogleMobileAds SDK is NOT available - ads will be skipped")
        print("AppDelegate: Please add Google Mobile Ads SDK via SPM:")
        print("  1. File → Add Package Dependencies...")
        print("  2. URL: https://github.com/googleads/swift-package-manager-google-mobile-ads")
        print("  3. Add to Target: MuscleBuildingRecorder (iOS only)")
        #endif

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // ATTリクエストはアプリがアクティブになった後に行う必要がある
        requestTrackingAuthorization()
    }

    /// App Tracking Transparency (ATT) 許可リクエスト
    /// SwiftUI ScenePhaseから呼び出し可能
    func requestTrackingAuthorization() {
        // iOS 14以上でのみATTが必要
        if #available(iOS 14, *) {
            // 既に許可/拒否が決定されている場合はスキップ
            let status = ATTrackingManager.trackingAuthorizationStatus
            if status == .notDetermined {
                // 少し遅延させてUIが完全に表示されてからダイアログを出す
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ATTrackingManager.requestTrackingAuthorization { status in
                        print("AppDelegate: ATT authorization status: \(status.rawValue)")
                        // ATT結果に関わらずAdMobを初期化
                        self.initializeAdMob()
                    }
                }
            } else {
                print("AppDelegate: ATT already determined: \(status.rawValue)")
                initializeAdMob()
            }
        } else {
            // iOS 14未満はそのままAdMobを初期化
            initializeAdMob()
        }
    }

    /// AdMob SDKの初期化
    private func initializeAdMob() {
        #if canImport(GoogleMobileAds)
        // 既に初期化済みの場合はスキップ
        guard !isAdMobInitialized else { return }
        isAdMobInitialized = true

        print("AppDelegate: Initializing GoogleMobileAds SDK...")
        MobileAds.shared.start { status in
            print("AdMob SDK initialized with status: \(status.adapterStatusesByClassName)")

            #if DEBUG
            // シミュレータ用テストデバイスIDを設定
            // v12+ではシミュレータは自動的にテストデバイスとして認識される
            print("AppDelegate: Running in DEBUG mode (simulator auto-detected as test device)")
            #endif

            // 広告を事前読み込み
            RewardedAdManager.shared.preloadAd()
        }
        #endif
    }

    private var isAdMobInitialized = false
}
