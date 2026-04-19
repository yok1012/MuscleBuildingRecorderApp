import Foundation
import WidgetKit
import Combine

/// Widget/Live Activity用の状態ストア
/// App Groupを介して状態を共有
final class WidgetStateStore: ObservableObject {
    static let shared = WidgetStateStore()

    // MARK: - Published Properties
    @Published private(set) var currentState: WorkoutStateSnapshot = .empty
    @Published private(set) var restNotificationSettings: [RestNotificationSetting] = RestNotificationSetting.defaultSettings
    @Published private(set) var heartRateZoneSettings: HeartRateZoneSettings = .defaultSettings

    // MARK: - Private Properties
    private let userDefaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var lastWidgetUpdate: Date = .distantPast
    // Widget UI で非ライブ項目（心拍数/重量/種目など）を素早く反映するため短めに。
    // フェーズ経過時間は Widget 側が Text(…, style: .timer) で OS ネイティブに秒単位更新するため、
    // ここで頻繁に reloadTimelines しなくても時計表示は動く。
    private let minimumWidgetUpdateInterval: TimeInterval = 3

    // MARK: - Initialization
    private init() {
        userDefaults = AppGroupConfig.sharedUserDefaults

        // 初期データの読み込み
        loadRestNotificationSettings()
        loadHeartRateZoneSettings()
        loadCurrentState()
    }

    // MARK: - Workout State Management

    /// ワークアウト状態を更新（SessionManagerから呼び出し）
    func updateWorkoutState(_ state: WorkoutStateSnapshot) {
        currentState = state

        // App Groupに保存
        saveState(state)

        // Widget更新（頻度制限付き）
        updateWidgetIfNeeded()
    }

    /// 状態をApp Groupに保存
    private func saveState(_ state: WorkoutStateSnapshot) {
        guard let userDefaults = userDefaults else { return }

        do {
            let data = try encoder.encode(state)
            userDefaults.set(data, forKey: WidgetStateKeys.workoutState)
            userDefaults.set(Date(), forKey: WidgetStateKeys.lastUpdateTimestamp)
        } catch {
            print("WidgetStateStore: Failed to save state: \(error)")
        }
    }

    /// App Groupから状態を読み込み
    private func loadCurrentState() {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: WidgetStateKeys.workoutState) else {
            return
        }

        do {
            currentState = try decoder.decode(WorkoutStateSnapshot.self, from: data)
        } catch {
            print("WidgetStateStore: Failed to load state: \(error)")
        }
    }

    /// Widgetを更新（頻度制限あり）
    private func updateWidgetIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastWidgetUpdate) >= minimumWidgetUpdateInterval else {
            return
        }

        lastWidgetUpdate = now
        WidgetCenter.shared.reloadTimelines(ofKind: "WorkoutWidget")
    }

    /// 強制的にWidget更新（状態遷移時など）
    func forceWidgetUpdate() {
        lastWidgetUpdate = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: "WorkoutWidget")
    }

    // MARK: - Rest Notification Settings Management

    /// 休憩通知設定を保存
    func saveRestNotificationSettings(_ settings: [RestNotificationSetting]) {
        restNotificationSettings = settings

        guard let userDefaults = userDefaults else { return }

        do {
            let data = try encoder.encode(settings)
            userDefaults.set(data, forKey: WidgetStateKeys.restNotificationSettings)
        } catch {
            print("WidgetStateStore: Failed to save rest notification settings: \(error)")
        }
    }

    /// 休憩通知設定を読み込み
    private func loadRestNotificationSettings() {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: WidgetStateKeys.restNotificationSettings) else {
            return
        }

        do {
            restNotificationSettings = try decoder.decode([RestNotificationSetting].self, from: data)
        } catch {
            print("WidgetStateStore: Failed to load rest notification settings: \(error)")
        }
    }

    /// 特定の設定を更新
    func updateRestNotificationSetting(at index: Int, setting: RestNotificationSetting) {
        guard index >= 0 && index < restNotificationSettings.count else { return }
        restNotificationSettings[index] = setting
        saveRestNotificationSettings(restNotificationSettings)
    }

    // MARK: - Heart Rate Zone Settings Management

    /// 心拍ゾーン設定を保存
    func saveHeartRateZoneSettings(_ settings: HeartRateZoneSettings) {
        heartRateZoneSettings = settings

        guard let userDefaults = userDefaults else { return }

        do {
            let data = try encoder.encode(settings)
            userDefaults.set(data, forKey: WidgetStateKeys.heartRateZoneSettings)
        } catch {
            print("WidgetStateStore: Failed to save heart rate zone settings: \(error)")
        }
    }

    /// 心拍ゾーン設定を読み込み
    private func loadHeartRateZoneSettings() {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: WidgetStateKeys.heartRateZoneSettings) else {
            return
        }

        do {
            heartRateZoneSettings = try decoder.decode(HeartRateZoneSettings.self, from: data)
        } catch {
            print("WidgetStateStore: Failed to load heart rate zone settings: \(error)")
        }
    }

    // MARK: - Utility Methods

    /// 現在の心拍数から心拍ゾーンを取得
    func currentHeartRateZone(heartRate: Double) -> HeartRateZone {
        heartRateZoneSettings.zone(for: heartRate)
    }

    /// ワークアウト終了時のクリーンアップ
    func clearWorkoutState() {
        currentState = .empty
        saveState(.empty)
        forceWidgetUpdate()
    }

    /// 静的メソッド: App Groupから直接状態を読み込み（Widget用）
    static func loadStateFromAppGroup() -> WorkoutStateSnapshot {
        guard let userDefaults = AppGroupConfig.sharedUserDefaults,
              let data = userDefaults.data(forKey: WidgetStateKeys.workoutState) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(WorkoutStateSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }
}

// MARK: - SessionManager Integration Extension
extension SessionManager {
    /// WidgetStateStoreに状態を同期
    func syncToWidgetState() {
        let phaseElapsed = currentPhaseElapsedTime
        let restRemaining: Int? = currentPhase == .rest ? Int(max(0, restTimeLimit - phaseElapsed)) : nil
        let targetRest: Int? = currentPhase == .rest ? Int(restTimeLimit) : nil

        let snapshot = WorkoutStateSnapshot(
            phase: currentPhase.rawValue,
            phaseDisplayName: currentPhase.displayName,
            elapsedTimeString: elapsedTimeString,
            totalWorkTime: Int(totalWorkTime),
            totalRestTime: Int(totalRestTime),
            currentPhaseTime: Int(phaseElapsed),
            heartRate: Int(HeartRateManager.shared.currentHeartRate),
            cycleIndex: cycleIndex,
            exercise: selectedExercise,
            category: selectedCategory,
            load: currentLoad,
            reps: currentReps,
            timestamp: Date(),
            restRemainingTime: restRemaining,
            targetRestTime: targetRest
        )

        WidgetStateStore.shared.updateWorkoutState(snapshot)
    }

    /// 現在のフェーズの経過時間
    var currentPhaseElapsedTime: TimeInterval {
        guard let startTime = phaseStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}
