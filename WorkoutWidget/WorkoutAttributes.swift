//
//  WorkoutAttributes.swift
//  WorkoutWidget
//
//  Live Activity（Dynamic Island / ロック画面）用の共有 ActivityAttributes。
//  ── 重要 ──
//  この定義は iOS アプリ（MuscleBuildingRecorder/WorkoutAttributes.swift）と完全に
//  同一である必要がある。片方を変更したら必ず両方を同期させること。
//  （synchronized-groups では単一ファイルを複数ターゲットに所属させられないため、
//   同一内容の定義を両方のターゲットに置いている）
//

import ActivityKit
import Foundation

struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String              // "Work" / "Rest" / "Idle"
        var elapsedTime: String        // フォールバック用フォーマット済み文字列
        var heartRate: Int
        var exercise: String
        var category: String
        var cycleIndex: Int
        var load: Double
        var reps: Double
        /// OSネイティブのライブタイマー用。このフェーズが開始された時刻。
        var phaseStartTime: Date?
        /// V2.1: アクティビティドメイン（"workout" / "study" / "work"）
        /// 既存 Live Activity との後方互換のため Optional（nil → workout）
        var domain: String?
    }

    /// セッション開始時刻
    var startTime: Date
}
