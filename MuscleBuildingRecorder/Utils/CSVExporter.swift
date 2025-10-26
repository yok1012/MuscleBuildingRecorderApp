import Foundation
import CoreData

class CSVExporter {
    static func export(sessions: [Session]) -> String {
        var csv = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.timeZone = TimeZone.current

        // ヘッダー行を追加
        csv += "セッションID,セッション開始日時,セッション終了日時,合計ワーク時間(秒),合計レスト時間(秒),合計ボリューム,サイクル,フェーズ,開始時刻,終了時刻,カテゴリー,種目,負荷,回数,メモ,平均心拍数,最大心拍数,最小心拍数,心拍勾配\n"

        for session in sessions {
            let sessionId = session.id?.uuidString ?? ""
            let sessionStart = session.startedAt != nil ? dateFormatter.string(from: session.startedAt!) : ""
            let sessionEnd = session.endedAt != nil ? dateFormatter.string(from: session.endedAt!) : ""
            let totalWorkSec = session.totalWorkSec
            let totalRestSec = session.totalRestSec
            let totalVolume = session.totalVolume

            // SetRecordsを取得してソート
            guard let setRecords = session.setRecords?.allObjects as? [SetRecord] else {
                // レコードが無い場合でもセッション情報は出力
                csv += "\"\(sessionId)\",\"\(sessionStart)\",\"\(sessionEnd)\",\(totalWorkSec),\(totalRestSec),\(totalVolume),,,,,,,,,,,,,\n"
                continue
            }

            let sortedRecords = setRecords.sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }

            if sortedRecords.isEmpty {
                // レコードが空の場合もセッション情報は出力
                csv += "\"\(sessionId)\",\"\(sessionStart)\",\"\(sessionEnd)\",\(totalWorkSec),\(totalRestSec),\(totalVolume),,,,,,,,,,,,,\n"
            } else {
                for record in sortedRecords {
                    let cycleIndex = record.cycleIndex
                    let phase = escapeCSV(record.phase ?? "")
                    let startTime = record.startAt != nil ? dateFormatter.string(from: record.startAt!) : ""
                    let endTime = record.endAt != nil ? dateFormatter.string(from: record.endAt!) : ""
                    let category = escapeCSV(record.category ?? "")
                    let name = escapeCSV(record.name ?? "")
                    let load = formatDouble(record.load)
                    let reps = formatDouble(record.reps)
                    let note = escapeCSV(record.note ?? "")
                    let hrAvg = formatDouble(record.hrAvg)
                    let hrMax = formatDouble(record.hrMax)
                    let hrMin = formatDouble(record.hrMin)
                    let hrSlope = formatDouble(record.hrSlopeAvg)

                    csv += "\"\(sessionId)\",\"\(sessionStart)\",\"\(sessionEnd)\",\(totalWorkSec),\(totalRestSec),\(formatDouble(totalVolume)),\(cycleIndex),\"\(phase)\",\"\(startTime)\",\"\(endTime)\",\"\(category)\",\"\(name)\",\(load),\(reps),\"\(note)\",\(hrAvg),\(hrMax),\(hrMin),\(hrSlope)\n"
                }
            }
        }

        return csv
    }

    // セッションサマリーのみをエクスポート
    static func exportSummary(sessions: [Session]) -> String {
        var csv = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.timeZone = TimeZone.current

        // ヘッダー行
        csv += "セッションID,開始日時,終了日時,合計時間(分),ワーク時間(分),レスト時間(分),合計ボリューム,セット数,平均心拍数,最大心拍数\n"

        for session in sessions {
            let sessionId = session.id?.uuidString ?? ""
            let sessionStart = session.startedAt != nil ? dateFormatter.string(from: session.startedAt!) : ""
            let sessionEnd = session.endedAt != nil ? dateFormatter.string(from: session.endedAt!) : ""

            let totalMinutes = (session.totalWorkSec + session.totalRestSec) / 60
            let workMinutes = session.totalWorkSec / 60
            let restMinutes = session.totalRestSec / 60
            let totalVolume = session.totalVolume

            // SetRecordsから統計を計算
            var setCount = 0
            var totalHrAvg = 0.0
            var maxHr = 0.0
            var avgCount = 0

            if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
                setCount = setRecords.count

                for record in setRecords {
                    if record.hrAvg > 0 {
                        totalHrAvg += record.hrAvg
                        avgCount += 1
                    }
                    if record.hrMax > maxHr {
                        maxHr = record.hrMax
                    }
                }
            }

            let avgHr = avgCount > 0 ? totalHrAvg / Double(avgCount) : 0.0

            csv += "\"\(sessionId)\",\"\(sessionStart)\",\"\(sessionEnd)\",\(totalMinutes),\(workMinutes),\(restMinutes),\(formatDouble(totalVolume)),\(setCount),\(formatDouble(avgHr)),\(formatDouble(maxHr))\n"
        }

        return csv
    }

    // CSV用の文字列エスケープ処理
    private static func escapeCSV(_ str: String) -> String {
        if str.contains("\"") || str.contains(",") || str.contains("\n") || str.contains("\r") {
            return str.replacingOccurrences(of: "\"", with: "\"\"")
        }
        return str
    }

    // Double値のフォーマット
    private static func formatDouble(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}