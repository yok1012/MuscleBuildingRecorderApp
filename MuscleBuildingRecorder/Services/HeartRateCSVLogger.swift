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

    /// フェーズ終了時に種目情報を補完
    /// - Parameters:
    ///   - phaseStartTimestamp: フェーズ開始時のタイムスタンプ（ミリ秒）
    ///   - phaseEndTimestamp: フェーズ終了時のタイムスタンプ（ミリ秒）
    ///   - category: カテゴリー
    ///   - exercise: 種目名
    ///   - reps: 回数
    ///   - load: 重量
    ///   - note: メモ
    func supplementPhaseData(
        phaseStartTimestamp: Int64,
        phaseEndTimestamp: Int64,
        category: String,
        exercise: String,
        reps: Double,
        load: Double,
        note: String
    ) {
        // ファイルハンドルを一旦閉じる
        closeFileHandle()

        let url = currentCSVURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("HeartRateCSVLogger: CSV file not found for supplementing")
            return
        }

        do {
            // CSVファイルを読み込み
            var content = try String(contentsOf: url, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")

            // 特殊文字をエスケープ（CSV用）
            let escapedCategory = escapeCSV(category)
            let escapedExercise = escapeCSV(exercise)
            let escapedNote = escapeCSV(note)

            var modifiedCount = 0

            // 各行を処理
            for i in 1..<lines.count {  // ヘッダーをスキップ
                let line = lines[i]
                guard !line.isEmpty else { continue }

                let columns = parseCSVLine(line)
                guard columns.count >= 10,
                      let timestamp = Int64(columns[0]) else { continue }

                // タイムスタンプが範囲内かチェック
                if timestamp >= phaseStartTimestamp && timestamp <= phaseEndTimestamp {
                    // 種目情報が空、かつメモも空の場合のみ補完
                    // （recordInstantNote で書かれた行は note が埋まっているため上書きされない）
                    if columns[5].isEmpty && columns[9].isEmpty {
                        // 新しい行を構築
                        var newColumns = columns
                        newColumns[5] = escapedCategory
                        newColumns[6] = escapedExercise
                        newColumns[7] = String(format: "%.0f", reps)
                        newColumns[8] = String(format: "%.1f", load)
                        newColumns[9] = escapedNote

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

    // MARK: - Cleanup

    deinit {
        closeFileHandle()
    }
}
