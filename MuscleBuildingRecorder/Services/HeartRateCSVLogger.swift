//
//  HeartRateCSVLogger.swift
//  MuscleBuildingRecorder
//
//  心拍数の時系列データをCSVに記録し、フェーズ切り替わり時に種目情報を補完
//

import Foundation
import Combine

/// 心拍数CSVログマネージャー
/// - 心拍数を時系列でCSVに記録
/// - フェーズ（work/rest）を記録
/// - 回数・種目はフェーズ切り替わり時に後から補完
final class HeartRateCSVLogger: ObservableObject {
    static let shared = HeartRateCSVLogger()

    // MARK: - Published Properties
    @Published var isLogging: Bool = false
    @Published var logCount: Int = 0

    // MARK: - Private Properties
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var logDirectory: URL { documentsURL.appendingPathComponent("SensorLogs") }
    private let csvDateFormatter: DateFormatter
    private let isoDateFormatter: DateFormatter
    private var fileHandle: FileHandle?
    private var currentDate: String = ""

    // 現在のフェーズ情報（補完用）
    private var currentPhaseStartTimestamp: Int64?
    private var currentPhase: String = "idle"
    private var currentCycleIndex: Int = 0

    // CSVヘッダー
    private let csvHeader = "timestamp_ms,datetime,heartRate,phase,cycleIndex,category,exercise,reps,load,note"

    // MARK: - Initialization
    private init() {
        self.csvDateFormatter = DateFormatter()
        self.csvDateFormatter.dateFormat = "yyyyMMdd"
        self.csvDateFormatter.timeZone = TimeZone.current

        self.isoDateFormatter = DateFormatter()
        self.isoDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.isoDateFormatter.timeZone = TimeZone.current

        ensureLogDirectory()
    }

    // MARK: - Public Methods

    /// セッション開始時に呼び出し
    func startSession() {
        DispatchQueue.main.async {
            self.isLogging = true
            self.logCount = 0
            self.currentPhaseStartTimestamp = nil
            self.currentPhase = "idle"
            self.currentCycleIndex = 0
        }
    }

    /// セッション終了時に呼び出し
    func endSession() {
        closeFileHandle()
        DispatchQueue.main.async {
            self.isLogging = false
        }
    }

    /// フェーズ変更時に呼び出し（補完なし - フェーズ開始用）
    func setPhase(_ phase: String, cycleIndex: Int) {
        currentPhase = phase
        currentCycleIndex = cycleIndex
        currentPhaseStartTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// 心拍数ログを追加（メインの記録メソッド）
    func logHeartRate(_ heartRate: Double) {
        guard isLogging, heartRate > 0 else { return }

        // idleフェーズは記録しない
        guard currentPhase != "idle" else { return }

        let now = Date()
        let timestamp = Int64(now.timeIntervalSince1970 * 1000)
        let datetime = isoDateFormatter.string(from: now)

        // 種目情報は空（後で補完）
        let line = "\(timestamp),\(datetime),\(heartRate),\(currentPhase),\(currentCycleIndex),,,,,\n"

        writeToCSV(line: line)

        DispatchQueue.main.async {
            self.logCount += 1
        }
    }

    /// 任意タイミングのメモを1行として記録する（行単位で心拍数と紐付け）
    /// - 既存の心拍数行と同じフォーマットで書き込み、note 列に本文を入れる
    /// - category / exercise / reps / load は空のまま。ただし note が埋まっているため
    ///   `supplementPhaseData` の補完対象外になる（フェーズ情報で上書きされない）
    func recordInstantNote(text: String, heartRate: Double) {
        guard isLogging else { return }
        guard currentPhase != "idle" else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        let timestamp = Int64(now.timeIntervalSince1970 * 1000)
        let datetime = isoDateFormatter.string(from: now)
        let escapedNote = escapeCSV(trimmed)

        // 心拍数が未取得（0）の場合はそのまま 0 として記録
        let line = "\(timestamp),\(datetime),\(heartRate),\(currentPhase),\(currentCycleIndex),,,,,\(escapedNote)\n"

        writeToCSV(line: line)

        DispatchQueue.main.async {
            self.logCount += 1
        }
    }

    /// フェーズ終了時に種目情報を補完（V2: note は引数を受けても書き込まない）
    /// - Parameters:
    ///   - phaseStartTimestamp: フェーズ開始時のタイムスタンプ（ミリ秒）
    ///   - phaseEndTimestamp: フェーズ終了時のタイムスタンプ（ミリ秒）
    ///   - category: カテゴリー
    ///   - exercise: 種目名
    ///   - reps: 回数
    ///   - load: 重量
    ///   - note: 互換のため引数は残すが、補完では一切使わない（メモは独立イベント保存）
    func supplementPhaseData(
        phaseStartTimestamp: Int64,
        phaseEndTimestamp: Int64,
        category: String,
        exercise: String,
        reps: Double,
        load: Double,
        note: String
    ) {
        _ = note

        closeFileHandle()

        let url = currentCSVURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("HeartRateCSVLogger: CSV file not found for supplementing")
            return
        }

        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")

            let escapedCategory = escapeCSV(category)
            let escapedExercise = escapeCSV(exercise)

            var modifiedCount = 0

            for i in 1..<lines.count {
                let line = lines[i]
                guard !line.isEmpty else { continue }

                let columns = parseCSVLine(line)
                guard columns.count >= 10,
                      let timestamp = Int64(columns[0]) else { continue }

                if timestamp >= phaseStartTimestamp && timestamp <= phaseEndTimestamp {
                    // category が空のときのみ補完。note 列はこの関数では決して書き換えない。
                    if columns[5].isEmpty {
                        var newColumns = columns
                        newColumns[5] = escapedCategory
                        newColumns[6] = escapedExercise
                        newColumns[7] = String(format: "%.0f", reps)
                        newColumns[8] = String(format: "%.1f", load)
                        // newColumns[9] (note) は触らない
                        lines[i] = newColumns.joined(separator: ",")
                        modifiedCount += 1
                    }
                }
            }

            // 変更があれば書き戻し
            if modifiedCount > 0 {
                content = lines.joined(separator: "\n")
                try content.write(to: url, atomically: true, encoding: .utf8)
                print("HeartRateCSVLogger: Supplemented \(modifiedCount) records with exercise data")
            }

        } catch {
            print("HeartRateCSVLogger: Failed to supplement phase data: \(error)")
        }
    }

    /// 現在のCSVファイルURL
    func currentCSVURL() -> URL {
        let dateString = csvDateFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("heartrate_\(dateString).csv")
    }

    /// 全ての心拍数ログファイルを取得
    func getAllHeartRateLogFiles() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.lastPathComponent.hasPrefix("heartrate_") && $0.pathExtension == "csv" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            print("HeartRateCSVLogger: Failed to list log files: \(error)")
            return []
        }
    }

    /// ログファイルを削除
    func deleteLogFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("HeartRateCSVLogger: Failed to delete log file: \(error)")
        }
    }

    /// 特定の日付の心拍数ログファイルのURLを取得
    func getLogFile(for date: Date) -> URL? {
        let dateString = csvDateFormatter.string(from: date)
        let url = logDirectory.appendingPathComponent("heartrate_\(dateString).csv")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 特定の日付の心拍数ログをJSON形式で取得
    func getLogDataAsJSON(for date: Date) -> Data? {
        guard let url = getLogFile(for: date) else { return nil }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            guard lines.count > 1 else { return nil }

            // ヘッダーをスキップして各行をパース
            var records: [[String: Any]] = []
            for i in 1..<lines.count {
                let columns = parseCSVLine(lines[i])
                guard columns.count >= 10 else { continue }

                let record: [String: Any] = [
                    "timestamp_ms": Int64(columns[0]) ?? 0,
                    "datetime": columns[1],
                    "heartRate": Double(columns[2]) ?? 0,
                    "phase": columns[3],
                    "cycleIndex": Int(columns[4]) ?? 0,
                    "category": columns[5],
                    "exercise": columns[6],
                    "reps": Double(columns[7]) ?? 0,
                    "load": Double(columns[8]) ?? 0,
                    "note": columns[9]
                ]
                records.append(record)
            }

            return try JSONSerialization.data(withJSONObject: records, options: .prettyPrinted)
        } catch {
            print("HeartRateCSVLogger: Failed to convert to JSON: \(error)")
            return nil
        }
    }

    // MARK: - Private Methods

    private func ensureLogDirectory() {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                print("HeartRateCSVLogger: Failed to create log directory: \(error)")
            }
        }
    }

    private func writeToCSV(line: String) {
        let dateString = csvDateFormatter.string(from: Date())

        // 日付が変わったらファイルハンドルを更新
        if currentDate != dateString {
            closeFileHandle()
            currentDate = dateString
        }

        let url = currentCSVURL()

        // ファイルが存在しない場合はヘッダーを書き込み
        if !FileManager.default.fileExists(atPath: url.path) {
            let header = csvHeader + "\n"
            do {
                try header.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("HeartRateCSVLogger: Failed to write CSV header: \(error)")
                return
            }
        }

        // ファイルハンドルを取得または作成
        if fileHandle == nil {
            do {
                fileHandle = try FileHandle(forWritingTo: url)
                try fileHandle?.seekToEnd()
            } catch {
                print("HeartRateCSVLogger: Failed to open file handle: \(error)")
                return
            }
        }

        // データを追記
        if let data = line.data(using: .utf8) {
            do {
                try fileHandle?.write(contentsOf: data)
            } catch {
                print("HeartRateCSVLogger: Failed to write data: \(error)")
            }
        }
    }

    private func closeFileHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    /// CSV用にエスケープ
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    /// CSV行をパース（ダブルクォート対応）
    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)

        return columns
    }

    // MARK: - Range Aggregation (エクスポート時にセット範囲で集計)

    /// 心拍数の生サンプル
    struct Sample {
        let timestamp: Date
        let bpm: Double
        let phase: String
        let cycleIndex: Int
    }

    /// 範囲集計結果
    struct RangeStats {
        let avg: Double
        let max: Double
        let min: Double
        /// 線形回帰の傾き (bpm / 分)
        let slope: Double
        let sampleCount: Int
    }

    /// 指定期間（[start, end]）の心拍サンプルを CSV から読む。
    /// 期間が日跨ぎの場合は該当する全 CSV を結合する。
    func loadSamples(from start: Date, to end: Date) -> [Sample] {
        guard end >= start else { return [] }

        // 念のためファイルハンドルを閉じてバッファされた書き込みを確定
        closeFileHandle()

        var samples: [Sample] = []
        var cursor = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)

        while cursor <= endDay {
            let dateString = csvDateFormatter.string(from: cursor)
            let url = logDirectory.appendingPathComponent("heartrate_\(dateString).csv")
            if FileManager.default.fileExists(atPath: url.path) {
                samples.append(contentsOf: parseFile(at: url, from: start, to: end))
            }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    /// 指定期間の集計値を計算する
    func computeStats(from start: Date, to end: Date) -> RangeStats? {
        let samples = loadSamples(from: start, to: end).filter { $0.bpm > 0 }
        guard !samples.isEmpty else { return nil }

        let bpms = samples.map { $0.bpm }
        let avg = bpms.reduce(0, +) / Double(bpms.count)
        let maxV = bpms.max() ?? 0
        let minV = bpms.min() ?? 0

        // 線形回帰: x は分単位の経過時間
        let slope: Double
        if samples.count >= 2 {
            let baseTime = samples.first!.timestamp.timeIntervalSince1970
            let xs = samples.map { ($0.timestamp.timeIntervalSince1970 - baseTime) / 60.0 }
            let ys = bpms
            let xMean = xs.reduce(0, +) / Double(xs.count)
            let yMean = ys.reduce(0, +) / Double(ys.count)
            var num = 0.0
            var den = 0.0
            for i in 0..<xs.count {
                num += (xs[i] - xMean) * (ys[i] - yMean)
                den += (xs[i] - xMean) * (xs[i] - xMean)
            }
            slope = den == 0 ? 0 : num / den
        } else {
            slope = 0
        }

        return RangeStats(avg: avg, max: maxV, min: minV, slope: slope, sampleCount: samples.count)
    }

    private func parseFile(at url: URL, from start: Date, to end: Date) -> [Sample] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Sample] = []
        let lines = content.components(separatedBy: "\n")

        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(end.timeIntervalSince1970 * 1000)

        for i in 1..<lines.count {
            let line = lines[i]
            guard !line.isEmpty else { continue }
            let cols = parseCSVLine(line)
            guard cols.count >= 5,
                  let ts = Int64(cols[0]),
                  ts >= startMs, ts <= endMs,
                  let bpm = Double(cols[2])
            else { continue }
            let phase = cols[3]
            let cycleIndex = Int(cols[4]) ?? 0
            result.append(Sample(
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0),
                bpm: bpm,
                phase: phase,
                cycleIndex: cycleIndex
            ))
        }
        return result
    }

    // MARK: - Cleanup

    deinit {
        closeFileHandle()
    }
}
