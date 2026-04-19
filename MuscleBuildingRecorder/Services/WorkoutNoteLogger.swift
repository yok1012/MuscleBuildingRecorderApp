//
//  WorkoutNoteLogger.swift
//  MuscleBuildingRecorder
//
//  トレーニング中の任意タイミングで残されたメモを時系列で記録する。
//  - メモリ内の `currentSessionNotes` に保持（UI表示用）
//  - `Documents/SensorLogs/notes_yyyyMMdd.csv` に永続化
//  - 各メモに phase / cycleIndex / その時点の心拍数 を紐付け、心拍数CSV とタイムスタンプで結合可能
//

import Foundation
import Combine

/// セッション中に残された一つ分のメモ
struct WorkoutNoteEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let phase: String       // "work" / "rest" / "idle"
    let cycleIndex: Int
    let text: String
    let heartRate: Double   // メモ入力時点の心拍数（0 = 不明）

    init(
        id: UUID = UUID(),
        timestamp: Date,
        phase: String,
        cycleIndex: Int,
        text: String,
        heartRate: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.cycleIndex = cycleIndex
        self.text = text
        self.heartRate = heartRate
    }
}

final class WorkoutNoteLogger: ObservableObject {
    static let shared = WorkoutNoteLogger()

    // MARK: - Published
    @Published private(set) var currentSessionNotes: [WorkoutNoteEntry] = []
    @Published private(set) var isLogging: Bool = false

    // MARK: - Paths / Formatters
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var logDirectory: URL { documentsURL.appendingPathComponent("SensorLogs") }
    private let csvHeader = "timestamp_ms,datetime,phase,cycleIndex,heartRate,text"
    private let isoDateFormatter: DateFormatter
    private let fileDateFormatter: DateFormatter
    private let ioQueue = DispatchQueue(label: "WorkoutNoteLogger.io", qos: .utility)

    // MARK: - Init
    private init() {
        isoDateFormatter = DateFormatter()
        isoDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        isoDateFormatter.timeZone = TimeZone.current

        fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyyMMdd"
        fileDateFormatter.timeZone = TimeZone.current

        ensureLogDirectory()
    }

    // MARK: - Session Lifecycle
    func startSession() {
        DispatchQueue.main.async {
            self.currentSessionNotes = []
            self.isLogging = true
        }
    }

    func endSession() {
        DispatchQueue.main.async {
            self.isLogging = false
        }
    }

    // MARK: - Recording
    /// 現在の状況で1件メモを追加する。空文字は無視する。
    /// - Returns: 追加された Entry（無効入力時は nil）
    @discardableResult
    func addNote(
        text: String,
        phase: String,
        cycleIndex: Int,
        heartRate: Double
    ) -> WorkoutNoteEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entry = WorkoutNoteEntry(
            timestamp: Date(),
            phase: phase,
            cycleIndex: cycleIndex,
            text: trimmed,
            heartRate: heartRate
        )

        DispatchQueue.main.async {
            self.currentSessionNotes.append(entry)
        }

        ioQueue.async { [weak self] in
            self?.appendToCSV(entry: entry)
        }

        return entry
    }

    // MARK: - Files
    func currentCSVURL() -> URL {
        logDirectory.appendingPathComponent("notes_\(fileDateFormatter.string(from: Date())).csv")
    }

    func getAllNoteLogFiles() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return files
                .filter { $0.lastPathComponent.hasPrefix("notes_") && $0.pathExtension == "csv" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            print("WorkoutNoteLogger: Failed to list note files: \(error)")
            return []
        }
    }

    // MARK: - Private
    private func ensureLogDirectory() {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                print("WorkoutNoteLogger: Failed to create log directory: \(error)")
            }
        }
    }

    private func appendToCSV(entry: WorkoutNoteEntry) {
        let url = currentCSVURL()

        if !FileManager.default.fileExists(atPath: url.path) {
            let header = csvHeader + "\n"
            do {
                try header.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("WorkoutNoteLogger: Failed to write header: \(error)")
                return
            }
        }

        let ts = Int64(entry.timestamp.timeIntervalSince1970 * 1000)
        let datetime = isoDateFormatter.string(from: entry.timestamp)
        let escapedText = escapeCSV(entry.text)
        let line = "\(ts),\(datetime),\(entry.phase),\(entry.cycleIndex),\(entry.heartRate),\(escapedText)\n"

        guard let data = line.data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            print("WorkoutNoteLogger: Failed to append: \(error)")
        }
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
