//
//  AppDelegate.swift
//  MuscleBuildingRecorder
//
//  AdMob SDK初期化用AppDelegate
//

import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // AdMob SDKの初期化
        #if canImport(GoogleMobileAds)
        print("AppDelegate: GoogleMobileAds SDK is available, initializing...")
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
        #else
        print("AppDelegate: ⚠️ GoogleMobileAds SDK is NOT available - ads will be skipped")
        print("AppDelegate: Please add Google Mobile Ads SDK via SPM:")
        print("  1. File → Add Package Dependencies...")
        print("  2. URL: https://github.com/googleads/swift-package-manager-google-mobile-ads")
        print("  3. Add to Target: MuscleBuildingRecorder (iOS only)")
        #endif

        return true
    }
}
