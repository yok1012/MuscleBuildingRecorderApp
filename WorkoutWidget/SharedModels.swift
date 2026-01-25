import Foundation
import SwiftUI

// MARK: - App Group Identifier
struct AppGroupConfig {
    static let appGroupIdentifier = "group.yokAppDev.MuscleBuildingRecorder"

    static var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

// MARK: - Workout State Snapshot (Widget/Live Activity用)
struct WorkoutStateSnapshot: Codable {
    let phase: String  // "idle", "work", "rest"
    let phaseDisplayName: String
    let elapsedTimeString: String
    let totalWorkTime: Int  // 秒
    let totalRestTime: Int  // 秒
    let currentPhaseTime: Int  // 秒
    let heartRate: Int
    let cycleIndex: Int
    let exercise: String
    let category: String
    let load: Double
    let reps: Double
    let timestamp: Date

    // 残り時間（restの場合、設定時間からの残り）
    let restRemainingTime: Int?
    let targetRestTime: Int?

    var isActive: Bool {
        phase != "idle"
    }

    var phaseColor: Color {
        switch phase {
        case "work": return .red
        case "rest": return .blue
        default: return .gray
        }
    }

    static var empty: WorkoutStateSnapshot {
        WorkoutStateSnapshot(
            phase: "idle",
            phaseDisplayName: "待機中",
            elapsedTimeString: "00:00",
            totalWorkTime: 0,
            totalRestTime: 0,
            currentPhaseTime: 0,
            heartRate: 0,
            cycleIndex: 0,
            exercise: "",
            category: "",
            load: 0,
            reps: 0,
            timestamp: Date(),
            restRemainingTime: nil,
            targetRestTime: nil
        )
    }
}

// MARK: - Widget State Keys
struct WidgetStateKeys {
    static let workoutState = "workoutState"
    static let restNotificationSettings = "restNotificationSettings"
    static let heartRateZoneSettings = "heartRateZoneSettings"
    static let lastUpdateTimestamp = "lastUpdateTimestamp"
}

// MARK: - WidgetStateStore (Widget用の静的読み込み)
struct WidgetStateStore {
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
