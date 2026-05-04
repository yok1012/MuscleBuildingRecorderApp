//
//  CSVExporter.swift (V2)
//  MuscleBuildingRecorder
//
//  V2 仕様の CSV エクスポート。
//  - ヘッダーに単位を明記 (例: 負荷(kg))
//  - 心拍はセット範囲で `HeartRateCSVLogger.computeStats` から再計算
//  - note 列はその SetRecord 期間中に記録されたメモ群を改行区切りで合体（独立イベント保持）
//

import Foundation
import CoreData

class CSVExporter {

    // MARK: - Detailed (per SetRecord)

    static func export(sessions: [Session]) -> String {
        let dateFormatter = makeDateFormatter()

        // ヘッダー行
        var csv = [
            "セッションID",
            "セッション開始日時",
            "セッション終了日時",
            "合計ワーク時間(秒)",
            "合計レスト時間(秒)",
            "合計ボリューム",
            "サイクル",
            "フェーズ",
            "開始時刻",
            "終了時刻",
            "カテゴリー",
            "種目",
            "負荷",
            "負荷単位",
            "回数",
            "回数単位",
            "メモ",
            "平均心拍数",
            "最大心拍数",
            "最小心拍数",
            "心拍勾配(bpm/分)",
            "心拍サンプル数"
        ].joined(separator: ",") + "\n"

        for session in sessions {
            let sessionId = session.id?.uuidString ?? ""
            let sessionStart = session.startedAt.map { dateFormatter.string(from: $0) } ?? ""
            let sessionEnd = session.endedAt.map { dateFormatter.string(from: $0) } ?? ""
            let totalWorkSec = session.totalWorkSec
            let totalRestSec = session.totalRestSec
            let totalVolume = session.totalVolume

            guard let setRecords = session.setRecords?.allObjects as? [SetRecord], !setRecords.isEmpty else {
                csv += [
                    quote(sessionId), quote(sessionStart), quote(sessionEnd),
                    "\(totalWorkSec)", "\(totalRestSec)", formatDouble(totalVolume),
                    "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""
                ].joined(separator: ",") + "\n"
                continue
            }

            let sortedRecords = setRecords.sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }

            for record in sortedRecords {
                let cycleIndex = record.cycleIndex
                let phase = quote(record.phase ?? "")
                let startTime = record.startAt.map { dateFormatter.string(from: $0) } ?? ""
                let endTime = record.endAt.map { dateFormatter.string(from: $0) } ?? ""
                let category = quote(record.category ?? "")
                let name = quote(record.name ?? "")
                let units = lookupUnits(name: record.name)
                let load = formatDouble(record.load)
                let reps = formatDouble(record.reps)

                // 範囲メモを CSV から拾い、改行区切りで合体（無ければ過去 SetRecord.note にフォールバック）
                let combinedNote: String
                if let s = record.startAt, let e = record.endAt {
                    let entries = WorkoutNoteLogger.shared.loadEntries(from: s, to: e)
                    if !entries.isEmpty {
                        combinedNote = entries.map { $0.text }.joined(separator: "\n")
                    } else {
                        combinedNote = (record.note ?? "")
                    }
                } else {
                    combinedNote = (record.note ?? "")
                }

                // 心拍は CSV から再計算（無ければ SetRecord 値）
                let stats = HeartRateCSVLogger.shared
                    .computeStats(from: record.startAt ?? .distantPast,
                                  to: record.endAt ?? Date.distantPast)
                let hrAvg = stats?.avg ?? record.hrAvg
                let hrMax = stats?.max ?? record.hrMax
                let hrMin = stats?.min ?? record.hrMin
                let hrSlope = stats?.slope ?? record.hrSlopeAvg
                let sampleCount = stats?.sampleCount ?? 0

                csv += [
                    quote(sessionId), quote(sessionStart), quote(sessionEnd),
                    "\(totalWorkSec)", "\(totalRestSec)", formatDouble(totalVolume),
                    "\(cycleIndex)", phase, quote(startTime), quote(endTime),
                    category, name,
                    load, quote(units.load),
                    reps, quote(units.reps),
                    quote(combinedNote),
                    formatDouble(hrAvg), formatDouble(hrMax), formatDouble(hrMin),
                    formatDouble(hrSlope), "\(sampleCount)"
                ].joined(separator: ",") + "\n"
            }
        }

        return csv
    }

    // MARK: - Summary (per Session)

    static func exportSummary(sessions: [Session]) -> String {
        let dateFormatter = makeDateFormatter()

        var csv = [
            "セッションID", "開始日時", "終了日時",
            "合計時間(分)", "ワーク時間(分)", "レスト時間(分)",
            "合計ボリューム", "重量単位",
            "セット数", "種目数",
            "平均心拍数", "最大心拍数", "最小心拍数",
            "メモ件数"
        ].joined(separator: ",") + "\n"

        for session in sessions {
            let sessionId = session.id?.uuidString ?? ""
            let sessionStart = session.startedAt.map { dateFormatter.string(from: $0) } ?? ""
            let sessionEnd = session.endedAt.map { dateFormatter.string(from: $0) } ?? ""

            let totalMinutes = (session.totalWorkSec + session.totalRestSec) / 60
            let workMinutes = session.totalWorkSec / 60
            let restMinutes = session.totalRestSec / 60
            let totalVolume = session.totalVolume

            let setRecords = (session.setRecords?.allObjects as? [SetRecord]) ?? []
            let workSets = setRecords.filter { $0.phase == "Work" }
            let setCount = workSets.count
            let exerciseCount = Set(setRecords.compactMap { $0.name }.filter { !$0.isEmpty }).count

            // セッション全期間で心拍再計算
            let s = session.startedAt ?? .distantPast
            let e = session.endedAt ?? Date()
            let stats = HeartRateCSVLogger.shared.computeStats(from: s, to: e)
            let avgHr = stats?.avg ?? 0
            let maxHr = stats?.max ?? 0
            let minHr = stats?.min ?? 0

            // 重量単位（混在は "mixed"）
            let weightUnit = dominantWeightUnit(records: setRecords)

            // メモ件数
            let noteCount = WorkoutNoteLogger.shared.loadEntries(from: s, to: e).count

            csv += [
                quote(sessionId), quote(sessionStart), quote(sessionEnd),
                "\(totalMinutes)", "\(workMinutes)", "\(restMinutes)",
                formatDouble(totalVolume), quote(weightUnit),
                "\(setCount)", "\(exerciseCount)",
                formatDouble(avgHr), formatDouble(maxHr), formatDouble(minHr),
                "\(noteCount)"
            ].joined(separator: ",") + "\n"
        }

        return csv
    }

    // MARK: - Helpers

    private static func makeDateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = TimeZone.current
        return f
    }

    private static func lookupUnits(name: String?) -> (load: String, reps: String) {
        guard let name, !name.isEmpty else { return ("kg", "回") }
        let request: NSFetchRequest<ExerciseMaster> = ExerciseMaster.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", name)
        request.fetchLimit = 1
        if let m = try? DataController.shared.container.viewContext.fetch(request).first {
            return (m.loadUnit ?? "kg", m.repsUnit ?? "回")
        }
        return ("kg", "回")
    }

    private static func dominantWeightUnit(records: [SetRecord]) -> String {
        let context = DataController.shared.container.viewContext
        var units = Set<String>()
        for record in records where record.phase == "Work" {
            guard let name = record.name, !name.isEmpty else { continue }
            let request: NSFetchRequest<ExerciseMaster> = ExerciseMaster.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", name)
            request.fetchLimit = 1
            if let m = try? context.fetch(request).first, let u = m.loadUnit, !u.isEmpty {
                units.insert(u)
            }
        }
        if units.isEmpty { return "kg" }
        if units.count == 1 { return units.first! }
        return "mixed"
    }

    /// CSV 用のクォート（カンマ・改行・ダブルクォートを含む値は囲む + エスケープ）
    private static func quote(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return "\"\(s)\""
    }

    private static func formatDouble(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}
