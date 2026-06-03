//
//  ActivityDomain.swift
//  MuscleBuildingRecorder
//
//  アクティビティの種別（筋トレ / 勉強 / 仕事）を表す列挙型。
//  既存の Session/SetRecord に Optional 属性として導入予定（Phase 1）。
//  - 既存データ（domain == nil）は .workout として扱う（legacyDefault）
//  - displayName/iconName/colorName は iOS/Watch/Widget 全ターゲットから参照可能（純 Swift のみ）
//

import Foundation

enum ActivityDomain: String, CaseIterable, Codable {
    case workout
    case study
    case work

    /// 既存データ互換のフォールバック先（domain 属性が無いセッション = 旧筋トレ記録）
    static let legacyDefault: ActivityDomain = .workout

    var displayName: String {
        switch self {
        case .workout: return "筋トレ".localizedSeed
        case .study:   return "勉強".localizedSeed
        case .work:    return "仕事".localizedSeed
        }
    }

    /// SF Symbols 名（Widget / Live Activity / 履歴セルから参照）
    var iconName: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .study:   return "book.fill"
        case .work:    return "briefcase.fill"
        }
    }

    /// 文字列カラー名。WorkoutPhase と同じ表現で、SwiftUI Color(name:) に渡せる。
    var colorName: String {
        switch self {
        case .workout: return "red"
        case .study:   return "blue"
        case .work:    return "green"
        }
    }

    /// Work フェーズ中の作業ラベル（ドメインによって意味が変わる）
    var workPhaseLabel: String {
        switch self {
        case .workout: return "筋トレ".localizedSeed
        case .study:   return "勉強".localizedSeed
        case .work:    return "作業".localizedSeed
        }
    }

    /// Rest フェーズ中の休憩ラベル
    var restPhaseLabel: String {
        switch self {
        case .workout: return "休憩".localizedSeed
        case .study:   return "休憩".localizedSeed
        case .work:    return "小休止".localizedSeed
        }
    }

    /// Work フェーズ進行中の「〜中」ラベル（English では現在進行形）
    var workPhaseActiveLabel: String {
        switch self {
        case .workout: return "筋トレ中".localizedSeed
        case .study:   return "勉強中".localizedSeed
        case .work:    return "作業中".localizedSeed
        }
    }

    /// Rest フェーズ進行中の「〜中」ラベル
    var restPhaseActiveLabel: String {
        switch self {
        case .workout, .study: return "休憩中".localizedSeed
        case .work:            return "小休止中".localizedSeed
        }
    }
}

// MARK: - Storage helpers

extension ActivityDomain {
    /// Core Data の String? カラムから安全にデコード（不明値・nil は legacyDefault）
    init(storedRawValue: String?) {
        guard
            let raw = storedRawValue,
            let value = ActivityDomain(rawValue: raw)
        else {
            self = .legacyDefault
            return
        }
        self = value
    }
}
