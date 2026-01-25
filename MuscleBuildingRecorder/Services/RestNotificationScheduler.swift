import Foundation
import Combine
import UserNotifications
import AudioToolbox
#if os(iOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// 休憩時間の通知をスケジュールするサービス
final class RestNotificationScheduler: ObservableObject {
    static let shared = RestNotificationScheduler()

    // MARK: - Properties
    private let notificationCenter = UNUserNotificationCenter.current()
    private var scheduledNotificationIds: [String] = []

    @Published var isAuthorized: Bool = false

    // MARK: - Initialization
    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// 通知の許可状態を確認
    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// 通知許可をリクエスト
    func requestAuthorization() async throws -> Bool {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run {
            isAuthorized = granted
        }
        return granted
    }

    // MARK: - Scheduling

    /// 休憩開始時に通知をスケジュール
    /// - Parameter settings: 休憩通知設定の配列
    func scheduleRestNotifications(settings: [RestNotificationSetting]) {
        // 既存の通知をキャンセル
        cancelAllRestNotifications()

        guard isAuthorized else {
            print("RestNotificationScheduler: Not authorized for notifications")
            return
        }

        for setting in settings where setting.isEnabled {
            scheduleNotification(for: setting)
        }
    }

    /// 個別の通知をスケジュール
    private func scheduleNotification(for setting: RestNotificationSetting) {
        // 振動回数分の通知をスケジュール（0.5秒間隔）
        for vibrationIndex in 0..<setting.vibrationCount {
            let delay = TimeInterval(setting.timeSeconds) + Double(vibrationIndex) * 0.5
            let notificationId = "rest_\(setting.id.uuidString)_\(vibrationIndex)"

            let content = UNMutableNotificationContent()

            // 最初の通知のみメッセージを設定
            if vibrationIndex == 0 {
                content.title = "休憩終了"
                content.body = "\(setting.timeDisplayString)が経過しました"
            } else {
                // 追加の振動用は空メッセージ
                content.title = ""
                content.body = ""
            }

            if setting.soundEnabled {
                content.sound = .default
            }

            // バッジカウントは使用しない
            content.badge = nil

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)

            notificationCenter.add(request) { error in
                if let error = error {
                    print("RestNotificationScheduler: Failed to schedule notification: \(error)")
                } else {
                    print("RestNotificationScheduler: Scheduled notification at \(delay)s")
                }
            }

            scheduledNotificationIds.append(notificationId)
        }
    }

    /// すべての休憩通知をキャンセル
    func cancelAllRestNotifications() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: scheduledNotificationIds)
        scheduledNotificationIds.removeAll()
        print("RestNotificationScheduler: Cancelled all rest notifications")
    }

    /// 特定の設定の通知のみキャンセル
    func cancelNotifications(for settingId: UUID) {
        let idsToRemove = scheduledNotificationIds.filter { $0.hasPrefix("rest_\(settingId.uuidString)") }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: idsToRemove)
        scheduledNotificationIds.removeAll { idsToRemove.contains($0) }
    }

    // MARK: - Haptic Feedback (iOS)

    #if os(iOS)
    /// バイブレーションを発生させる
    func playHapticFeedback(count: Int = 1) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }
    }
    #endif

    // MARK: - Watch Haptic (watchOS)

    #if os(watchOS)
    /// watchOSでバイブレーションを発生させる
    func playWatchHaptic(count: Int = 1) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
    #endif

    // MARK: - Pending Notifications Info

    /// 予定されている通知の数を取得
    func getPendingNotificationCount() async -> Int {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        return pendingRequests.filter { $0.identifier.hasPrefix("rest_") }.count
    }
}

// MARK: - SessionManager Integration
extension SessionManager {
    /// 休憩フェーズ開始時に通知をスケジュール
    func scheduleRestNotifications() {
        let settings = WidgetStateStore.shared.restNotificationSettings
        RestNotificationScheduler.shared.scheduleRestNotifications(settings: settings)
    }

    /// ワークアウトフェーズ開始時に通知をキャンセル
    func cancelRestNotifications() {
        RestNotificationScheduler.shared.cancelAllRestNotifications()
    }
}
