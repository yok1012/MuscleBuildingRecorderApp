import AppIntents
import WidgetKit

// MARK: - Toggle Phase Intent (ワーク/休憩切り替え)
struct TogglePhaseIntent: AppIntent {
    static var title: LocalizedStringResource = "フェーズ切り替え"
    static var description = IntentDescription("ワーク/休憩を切り替えます")

    func perform() async throws -> some IntentResult {
        // App Groupを通じてメインアプリに通知
        if let userDefaults = AppGroupConfig.sharedUserDefaults {
            userDefaults.set(true, forKey: "pendingPhaseToggle")
            userDefaults.synchronize()
        }

        // Widgetをリロード
        WidgetCenter.shared.reloadTimelines(ofKind: "WorkoutWidget")

        return .result()
    }
}

// MARK: - Start Workout Intent (ワークアウト開始)
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "ワークアウト開始"
    static var description = IntentDescription("ワークアウトを開始します")

    func perform() async throws -> some IntentResult {
        if let userDefaults = AppGroupConfig.sharedUserDefaults {
            userDefaults.set(true, forKey: "pendingStartWorkout")
            userDefaults.synchronize()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "WorkoutWidget")

        return .result()
    }
}

// MARK: - End Workout Intent (ワークアウト終了)
struct EndWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "ワークアウト終了"
    static var description = IntentDescription("ワークアウトを終了します")

    func perform() async throws -> some IntentResult {
        if let userDefaults = AppGroupConfig.sharedUserDefaults {
            userDefaults.set(true, forKey: "pendingEndWorkout")
            userDefaults.synchronize()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "WorkoutWidget")

        return .result()
    }
}
