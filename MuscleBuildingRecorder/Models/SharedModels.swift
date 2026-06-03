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

    /// V2.1: アクティビティドメイン（"workout" / "study" / "work"）。
    /// 既存の App Group データとの後方互換のため Optional（nil → workout）。
    let domain: String?

    var isActive: Bool {
        phase != "idle"
    }

    /// ドメイン未指定時は workout（旧データ互換）
    var domainResolved: String {
        domain ?? "workout"
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
            targetRestTime: nil,
            domain: nil
        )
    }
}

// MARK: - Session Persistence State (タスクキル時の復元用)
/// アプリ終了時に保存し、次回起動時に復元するためのセッション状態
struct SessionPersistenceState: Codable {
    let sessionId: String?           // Core Data SessionのUUID
    let phase: String                 // "idle", "work", "rest"
    let totalWorkTime: TimeInterval   // 累積ワーク時間
    let totalRestTime: TimeInterval   // 累積休憩時間
    let phaseStartTime: Date?         // 現在フェーズ開始時刻
    let sessionStartTime: Date?       // セッション開始時刻
    let cycleIndex: Int
    let selectedCategory: String
    let selectedExercise: String
    let currentLoad: Double
    let currentReps: Double
    let savedAt: Date                 // 保存時刻

    /// セッションが有効かどうか（idleでなく、保存から一定時間以内）
    var isValidForRestore: Bool {
        guard phase != "idle" else { return false }
        // 保存から24時間以内のみ有効
        let maxAge: TimeInterval = 24 * 60 * 60
        return Date().timeIntervalSince(savedAt) < maxAge
    }

    /// 保存からの経過時間（秒）
    var timeSinceSaved: TimeInterval {
        Date().timeIntervalSince(savedAt)
    }

    /// 表示用の経過時間文字列
    var timeSinceSavedString: String {
        let elapsed = Int(timeSinceSaved)
        if elapsed < 60 {
            return "\(elapsed)秒前"
        } else if elapsed < 3600 {
            return "\(elapsed / 60)分前"
        } else {
            return "\(elapsed / 3600)時間前"
        }
    }

    static var empty: SessionPersistenceState {
        SessionPersistenceState(
            sessionId: nil,
            phase: "idle",
            totalWorkTime: 0,
            totalRestTime: 0,
            phaseStartTime: nil,
            sessionStartTime: nil,
            cycleIndex: 0,
            selectedCategory: "胸",
            selectedExercise: "ベンチプレス",
            currentLoad: 40.0,
            currentReps: 10.0,
            savedAt: Date()
        )
    }
}

// MARK: - Rest Notification Setting (3種類の休憩通知設定)
struct RestNotificationSetting: Codable, Identifiable, Equatable {
    var id: UUID
    var isEnabled: Bool
    var timeSeconds: Int  // 30, 60, 90 など
    var vibrationCount: Int  // 1, 2, 3 など
    var soundEnabled: Bool

    var timeDisplayString: String {
        if timeSeconds >= 60 {
            let minutes = timeSeconds / 60
            let seconds = timeSeconds % 60
            if seconds > 0 {
                return "\(minutes)分\(seconds)秒"
            }
            return "\(minutes)分"
        }
        return "\(timeSeconds)秒"
    }

    static var defaultSettings: [RestNotificationSetting] {
        [
            RestNotificationSetting(id: UUID(), isEnabled: true, timeSeconds: 30, vibrationCount: 1, soundEnabled: true),
            RestNotificationSetting(id: UUID(), isEnabled: true, timeSeconds: 60, vibrationCount: 2, soundEnabled: true),
            RestNotificationSetting(id: UUID(), isEnabled: false, timeSeconds: 90, vibrationCount: 3, soundEnabled: true)
        ]
    }
}

// MARK: - Heart Rate Zone (心拍ゾーン定義)
enum HeartRateZone: Int, CaseIterable, Codable {
    case zone1 = 1  // 50-60% - 回復/ウォームアップ
    case zone2 = 2  // 60-70% - 脂肪燃焼
    case zone3 = 3  // 70-80% - 有酸素
    case zone4 = 4  // 80-90% - 無酸素/閾値
    case zone5 = 5  // 90-100% - 最大/VO2max

    var displayName: String {
        switch self {
        case .zone1: return "Zone 1"
        case .zone2: return "Zone 2"
        case .zone3: return "Zone 3"
        case .zone4: return "Zone 4"
        case .zone5: return "Zone 5"
        }
    }

    var description: String {
        switch self {
        case .zone1: return "回復".localizedSeed
        case .zone2: return "脂肪燃焼".localizedSeed
        case .zone3: return "有酸素".localizedSeed
        case .zone4: return "閾値".localizedSeed
        case .zone5: return "最大".localizedSeed
        }
    }

    var color: Color {
        switch self {
        case .zone1: return .gray
        case .zone2: return .blue
        case .zone3: return .green
        case .zone4: return .orange
        case .zone5: return .red
        }
    }

    var percentageRange: ClosedRange<Double> {
        switch self {
        case .zone1: return 0.50...0.60
        case .zone2: return 0.60...0.70
        case .zone3: return 0.70...0.80
        case .zone4: return 0.80...0.90
        case .zone5: return 0.90...1.00
        }
    }

    /// 最大心拍数と現在の心拍数からゾーンを判定
    static func zone(for heartRate: Double, maxHeartRate: Double) -> HeartRateZone {
        let percentage = heartRate / maxHeartRate

        switch percentage {
        case ..<0.50:
            return .zone1
        case 0.50..<0.60:
            return .zone1
        case 0.60..<0.70:
            return .zone2
        case 0.70..<0.80:
            return .zone3
        case 0.80..<0.90:
            return .zone4
        default:
            return .zone5
        }
    }

    /// 年齢から最大心拍数を計算（220 - 年齢）
    static func maxHeartRate(forAge age: Int) -> Double {
        return Double(220 - age)
    }
}

// MARK: - User Settings for Heart Rate Zone
struct HeartRateZoneSettings: Codable {
    var age: Int
    var customMaxHeartRate: Double?  // カスタム最大心拍数（指定がなければ年齢から計算）

    var maxHeartRate: Double {
        customMaxHeartRate ?? HeartRateZone.maxHeartRate(forAge: age)
    }

    static var defaultSettings: HeartRateZoneSettings {
        HeartRateZoneSettings(age: 30, customMaxHeartRate: nil)
    }

    func zone(for heartRate: Double) -> HeartRateZone {
        HeartRateZone.zone(for: heartRate, maxHeartRate: maxHeartRate)
    }

    func heartRateRange(for zone: HeartRateZone) -> ClosedRange<Int> {
        let range = zone.percentageRange
        let lower = Int(maxHeartRate * range.lowerBound)
        let upper = Int(maxHeartRate * range.upperBound)
        return lower...upper
    }
}

// MARK: - Widget State Keys
struct WidgetStateKeys {
    static let workoutState = "workoutState"
    static let restNotificationSettings = "restNotificationSettings"
    static let heartRateZoneSettings = "heartRateZoneSettings"
    static let lastUpdateTimestamp = "lastUpdateTimestamp"
    static let sessionPersistenceState = "sessionPersistenceState"
}
