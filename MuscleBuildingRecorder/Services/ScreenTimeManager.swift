//
//  ScreenTimeManager.swift
//  MuscleBuildingRecorder
//
//  Screen Time API（FamilyControls / ManagedSettings）を使って、筋トレ中に他アプリの使用を
//  制限する機能を提供する。
//
//  - セッション開始: `applyShield()`
//  - セッション終了 or 強制解除: `removeShield()`
//  - 休憩フェーズ（Pro のみ）: `startRestPhaseUnlock(isPro:)` で一時解除 → N 秒後に再ロック、
//    その M 秒前に警告通知
//  - 事故防止: `safetyCheckIfIdle(sessionActive:)` をアプリ起動時／active 時に呼ぶと、
//    セッションが idle なのに shield が残っている矛盾状態を検知して強制解除
//

import Foundation
import Combine
import UserNotifications

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

@available(iOS 16.0, *)
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    // MARK: - Published
    @Published private(set) var config: ScreenTimeConfig
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var hasActiveShield: Bool = false
    @Published private(set) var isInRestUnlockWindow: Bool = false

    // MARK: - Private
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("muscleBuildingRecorder.workout"))
    private let shieldActiveKey = "screenTime.shieldActive"
    private let shieldStartAtKey = "screenTime.shieldStartAt"
    private let warnNotificationID = "screenTime.relockWarning"

    private var relockWorkItem: DispatchWorkItem?

    // MARK: - Init
    private init() {
        self.config = ScreenTimeConfig.load()
        refreshAuthorizationStatus()
        refreshShieldState()
    }

    // MARK: - Authorization
    /// 認可をリクエスト（初回設定時にユーザー操作で呼ぶ）
    @MainActor
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            self.isAuthorized = (AuthorizationCenter.shared.authorizationStatus == .approved)
            self.config.authorizationGranted = self.isAuthorized
            self.saveConfig()
        } catch {
            print("ScreenTimeManager: ❌ Authorization failed: \(error)")
            self.isAuthorized = false
        }
    }

    func refreshAuthorizationStatus() {
        self.isAuthorized = (AuthorizationCenter.shared.authorizationStatus == .approved)
    }

    private func refreshShieldState() {
        hasActiveShield = AppGroupConfig.sharedUserDefaults?.bool(forKey: shieldActiveKey) ?? false
    }

    // MARK: - Config
    func updateConfig(_ newConfig: ScreenTimeConfig) {
        self.config = newConfig
        saveConfig()
    }

    private func saveConfig() {
        config.save()
    }

    // MARK: - Shield control

    /// 設定に応じてシールドを適用する。
    /// - 無料 / Pro いずれも、`exemptionSelection` のアプリトークンは常に除外される。
    /// - `shieldedSelection` が空のときは全カテゴリー shield（完全シャットアウト）
    /// - `shieldedSelection` に指定がある場合はそれに絞る（Pro のカスタム選択）
    func applyShield() {
        guard config.isEnabled else { return }
        guard isAuthorized else {
            print("ScreenTimeManager: ⚠️ applyShield skipped - not authorized")
            return
        }

        let shielded = config.shieldedSelection
        let exempt = config.exemptionSelection

        // アプリ個別シールド（Pro の選択がある場合のみ）
        store.shield.applications = shielded.applicationTokens.isEmpty ? nil : shielded.applicationTokens

        // カテゴリー shield
        if !shielded.categoryTokens.isEmpty {
            // Pro: 特定カテゴリーだけ shield（選択された除外アプリも考慮）
            store.shield.applicationCategories = .specific(shielded.categoryTokens, except: exempt.applicationTokens)
        } else if shielded.applicationTokens.isEmpty {
            // 無料 or 未選択: 全カテゴリー shield、除外アプリは外す
            store.shield.applicationCategories = .all(except: exempt.applicationTokens)
        } else {
            // Pro: アプリ個別指定のみで、カテゴリー指定なし
            store.shield.applicationCategories = .none
        }

        markShieldActive(true)
        print("ScreenTimeManager: 🛡️ Shield applied (apps=\(shielded.applicationTokens.count) cats=\(shielded.categoryTokens.count) exempt=\(exempt.applicationTokens.count))")
    }

    /// シールドを全解除する。
    func removeShield() {
        store.clearAllSettings()
        cancelRestUnlockTimers()
        markShieldActive(false)
        isInRestUnlockWindow = false
        print("ScreenTimeManager: 🔓 Shield removed")
    }

    private func markShieldActive(_ active: Bool) {
        hasActiveShield = active
        guard let defaults = AppGroupConfig.sharedUserDefaults else { return }
        defaults.set(active, forKey: shieldActiveKey)
        if active {
            defaults.set(Date(), forKey: shieldStartAtKey)
        } else {
            defaults.removeObject(forKey: shieldStartAtKey)
        }
    }

    // MARK: - Rest Phase Unlock (Pro)

    /// 休憩フェーズに入ったときに、一時的にシールドを解除する（Pro 機能）。
    /// - Parameter isPro: Pro ユーザーかどうか（false のときは何もしない）
    func startRestPhaseUnlock(isPro: Bool) {
        guard isPro, config.isEnabled, isAuthorized else { return }

        cancelRestUnlockTimers()

        // いったんシールドを外す
        store.clearAllSettings()
        isInRestUnlockWindow = true

        let unlockSeconds = max(5, config.restUnlockSeconds)
        let warnSeconds = max(0, min(config.warnBeforeRelockSeconds, unlockSeconds - 1))

        // 10 秒前に警告通知（ユーザー指定）
        if warnSeconds > 0 {
            let warnDelay = TimeInterval(unlockSeconds - warnSeconds)
            scheduleRelockWarning(after: warnDelay, warnSeconds: warnSeconds)
        }

        // 指定秒後に再ロック
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isInRestUnlockWindow = false
            self.applyShield()
        }
        relockWorkItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(unlockSeconds), execute: task)

        print("ScreenTimeManager: ⏱ Rest unlock for \(unlockSeconds)s (warn before \(warnSeconds)s)")
    }

    /// 休憩→筋トレ遷移などで解除ウィンドウをキャンセルし、即座に再ロック。
    func cancelRestUnlockAndReapply() {
        guard isInRestUnlockWindow else { return }
        cancelRestUnlockTimers()
        isInRestUnlockWindow = false
        applyShield()
    }

    private func cancelRestUnlockTimers() {
        relockWorkItem?.cancel()
        relockWorkItem = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [warnNotificationID])
    }

    private func scheduleRelockWarning(after delay: TimeInterval, warnSeconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "まもなく制限が再開されます"
        content.body = "あと \(warnSeconds) 秒で他アプリの使用制限が戻ります"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: warnNotificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("ScreenTimeManager: ⚠️ failed to schedule warning: \(error)") }
        }
    }

    // MARK: - Safety

    /// 起動時・active 時に呼ぶ整合性チェック。
    /// セッションが idle なのに shield が残っている矛盾状態を検知して強制解除する。
    func safetyCheckIfIdle(sessionActive: Bool) {
        refreshShieldState()
        if hasActiveShield && !sessionActive {
            print("ScreenTimeManager: 🛟 Safety check - removing stale shield (session is idle)")
            removeShield()
        }
    }
}
