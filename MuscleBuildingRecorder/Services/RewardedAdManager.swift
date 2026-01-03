//
//  RewardedAdManager.swift
//  MuscleBuildingRecorder
//
//  リワード広告の読み込みと表示を管理
//

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
import UIKit
import Combine

/// リワード広告の状態
enum AdState {
    case notLoaded
    case loading
    case ready
    case showing
    case failed(Error)
}

/// リワード広告を管理するシングルトン
/// iOSのみで動作。watchOSではスキップされる。
final class RewardedAdManager: NSObject, ObservableObject {
    static let shared = RewardedAdManager()

    /// 広告の現在の状態
    @Published private(set) var state: AdState = .notLoaded

    /// 広告が表示可能か
    var isAdReady: Bool {
        if case .ready = state { return true }
        return false
    }

    #if canImport(GoogleMobileAds)
    private var rewardedAd: RewardedAd?
    #endif

    /// 広告ユニットID
    private var adUnitID: String {
        #if DEBUG
        // テスト用広告ユニットID（Google公式テストID）
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        // 本番用広告ユニットID
        return "ca-app-pub-9111455054322479/8933621549"
        #endif
    }

    private var completionHandler: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    /// 広告を事前に読み込む
    func preloadAd() {
        #if canImport(GoogleMobileAds)
        print("RewardedAdManager: preloadAd called, current state = \(state)")
        guard case .notLoaded = state else {
            print("RewardedAdManager: State is not .notLoaded, checking other conditions...")
            guard case .failed = state else {
                if case .loading = state {
                    print("RewardedAdManager: Already loading, skipping")
                    return
                }
                if case .ready = state {
                    print("RewardedAdManager: Already ready, skipping")
                    return
                }
                if case .showing = state {
                    print("RewardedAdManager: Currently showing, skipping")
                    return
                }
                print("RewardedAdManager: Starting load from non-.notLoaded state")
                loadAd()
                return
            }
            print("RewardedAdManager: State is .failed, retrying load")
            loadAd()
            return
        }
        print("RewardedAdManager: State is .notLoaded, starting fresh load")
        loadAd()
        #else
        print("RewardedAdManager: ⚠️ GoogleMobileAds SDK not available - preloadAd is no-op")
        #endif
    }

    private func loadAd() {
        #if canImport(GoogleMobileAds)
        state = .loading

        RewardedAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    print("RewardedAdManager: Failed to load ad - \(error.localizedDescription)")
                    self.state = .failed(error)
                    return
                }

                self.rewardedAd = ad
                self.rewardedAd?.fullScreenContentDelegate = self
                self.state = .ready
                print("RewardedAdManager: Ad loaded successfully")
            }
        }
        #endif
    }

    /// 広告を表示
    /// - Parameter completion: 広告視聴完了時にtrue、失敗/スキップ時にfalse
    func showAd(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        #if canImport(GoogleMobileAds)
        print("RewardedAdManager: showAd called")
        guard let rewardedAd = rewardedAd else {
            print("RewardedAdManager: Ad not ready (rewardedAd is nil), completing with fallback")
            completion(false)
            return
        }

        self.completionHandler = completion
        state = .showing
        print("RewardedAdManager: Presenting ad from viewController: \(viewController)")

        rewardedAd.present(from: viewController) { [weak self] in
            // ユーザーが報酬を獲得
            print("RewardedAdManager: User earned reward")
            self?.completionHandler?(true)
            self?.completionHandler = nil
        }
        #else
        // GoogleMobileAdsが利用不可の場合は即完了
        print("RewardedAdManager: ⚠️ GoogleMobileAds SDK not available - showAd completing immediately")
        completion(true)
        #endif
    }

    /// 広告の状態をリセットして再読み込み
    func reset() {
        #if canImport(GoogleMobileAds)
        rewardedAd = nil
        #endif
        state = .notLoaded
        preloadAd()
    }
}

#if canImport(GoogleMobileAds)
// MARK: - FullScreenContentDelegate
extension RewardedAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("RewardedAdManager: Ad dismissed")
        // 広告が閉じられたら次の広告を読み込み
        state = .notLoaded
        preloadAd()

        // completionHandlerがまだ呼ばれていない場合（報酬なしで閉じた場合）
        // この場合でもリザルト画面へ遷移させる
        if let handler = completionHandler {
            handler(true) // dismiss時も遷移を許可
            completionHandler = nil
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("RewardedAdManager: Failed to present ad - \(error.localizedDescription)")
        state = .failed(error)

        completionHandler?(false)
        completionHandler = nil

        // 再読み込みを試みる
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reset()
        }
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("RewardedAdManager: Ad will present")
    }
}
#endif
