//
//  WorkoutPreset.swift
//  MuscleBuildingRecorder
//
//  ワークアウトプリセットのデータモデル。
//  - 拡張性のため、追加フィールドはすべて Optional で導入する
//  - ルートに schemaVersion を持ち、将来のマイグレーションに対応できる
//

import Foundation

/// プリセット内の 1 ステップ（種目）の設定。
/// 任意フィールドは将来の機能追加用（既存データを壊さないため Optional）。
struct WorkoutPresetStep: Codable, Identifiable, Equatable {
    var id: UUID
    var category: String        // 例: "胸"
    var exerciseName: String    // 例: "ベンチプレス"
    var workSeconds: Int        // 筋トレ時間 (秒)
    var restSeconds: Int        // 休憩時間 (秒)
    var setCount: Int           // セット回数

    // 任意（将来拡張）
    var defaultLoad: Double?
    var defaultReps: Double?
    var note: String?

    // V2: study/work ドメイン用フィールド（workout では未使用）
    var taskName: String?
    var subject: String?      // study 用
    var project: String?      // work 用

    init(
        id: UUID = UUID(),
        category: String = "胸",
        exerciseName: String = "ベンチプレス",
        workSeconds: Int = 30,
        restSeconds: Int = 60,
        setCount: Int = 3,
        defaultLoad: Double? = nil,
        defaultReps: Double? = nil,
        note: String? = nil,
        taskName: String? = nil,
        subject: String? = nil,
        project: String? = nil
    ) {
        self.id = id
        self.category = category
        self.exerciseName = exerciseName
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.setCount = setCount
        self.defaultLoad = defaultLoad
        self.defaultReps = defaultReps
        self.note = note
        self.taskName = taskName
        self.subject = subject
        self.project = project
    }

    var summaryText: String {
        "\(workSeconds)秒/\(restSeconds)秒 ×\(setCount)セット"
    }
}

/// 1 つのプリセット。
struct WorkoutPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// 自動進行フラグ。true の場合、設定した秒数経過で自動的にフェーズ遷移し、
    /// 全ステップ完了で自動的にセッション終了する。
    var autoAdvance: Bool
    var steps: [WorkoutPresetStep]

    // 任意（将来拡張）
    var iconName: String?
    var colorHex: String?

    /// V2: プリセットのドメイン。Optional + デフォルト workout で旧データ互換。
    /// rawValue として "workout" / "study" / "work" を保存。
    var domainRaw: String?

    /// 型安全な domain アクセサ（旧データの nil は workout として扱う）
    var domain: ActivityDomain {
        get { ActivityDomain(storedRawValue: domainRaw) }
        set { domainRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String = "新しいプリセット",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        autoAdvance: Bool = false,
        steps: [WorkoutPresetStep] = [],
        iconName: String? = nil,
        colorHex: String? = nil,
        domain: ActivityDomain = .workout
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.autoAdvance = autoAdvance
        self.steps = steps
        self.iconName = iconName
        self.colorHex = colorHex
        self.domainRaw = domain.rawValue
    }

    /// 概要表示（例: "3種目 / 計 9セット"）
    var summaryText: String {
        let totalSets = steps.reduce(0) { $0 + $1.setCount }
        switch domain {
        case .workout:
            return "\(steps.count)種目 / 計 \(totalSets)セット"
        case .study, .work:
            return "\(steps.count)タスク / 計 \(totalSets)サイクル"
        }
    }
}

/// プリセット保存ルート。schemaVersion でマイグレーションを管理。
/// schemaVersion 2: WorkoutPreset.domainRaw / WorkoutPresetStep.taskName/subject/project 追加
struct WorkoutPresetStore: Codable {
    var schemaVersion: Int
    var presets: [WorkoutPreset]

    static let currentSchemaVersion = 2

    init(
        schemaVersion: Int = WorkoutPresetStore.currentSchemaVersion,
        presets: [WorkoutPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.presets = presets
    }
}
