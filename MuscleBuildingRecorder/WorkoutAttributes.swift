//
//  WorkoutAttributes.swift
//  MuscleBuildingRecorder
//
//  Live Activity（Dynamic Island / ロック画面）用の共有 ActivityAttributes。
//  ── 重要 ──
//  この定義は iOS アプリ（本ファイル）と Widget Extension（WorkoutWidget/WorkoutAttributes.swift）で
//  完全に同一である必要がある。ActivityKit は Codable で ContentState / attributes を
//  JSON エンコードし Widget Extension プロセスに渡すため、フィールド構成がずれると
//  Widget 側でデコードに失敗し Dynamic Island が何も描画されない。
//  どちらか片方を変更したら必ず両方を同期させること。
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
