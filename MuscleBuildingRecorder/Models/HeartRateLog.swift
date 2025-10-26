import Foundation
import CoreData
import Combine

// 心拍数ログデータの構造体
struct HeartRateLogData: Codable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let heartRate: Double
    let phase: String // "Work" or "Rest"
    let cycleIndex: Int

    init(timestamp: Date, heartRate: Double, phase: String, cycleIndex: Int = 0) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.phase = phase
        self.cycleIndex = cycleIndex
    }
}

// 心拍数ログマネージャー（シングルトン）
class HeartRateLogManager: ObservableObject {
    static let shared = HeartRateLogManager()

    @Published var currentSessionLogs: [HeartRateLogData] = []
    private var sessionStartTime: Date?

    private init() {}

    func startNewSession() {
        currentSessionLogs = []
        sessionStartTime = Date()
    }

    func addLog(heartRate: Double, phase: String, cycleIndex: Int) {
        let log = HeartRateLogData(
            timestamp: Date(),
            heartRate: heartRate,
            phase: phase,
            cycleIndex: cycleIndex
        )
        currentSessionLogs.append(log)
    }

    func clearLogs() {
        currentSessionLogs = []
        sessionStartTime = nil
    }

    func getLogsForCycle(_ cycleIndex: Int) -> [HeartRateLogData] {
        return currentSessionLogs.filter { $0.cycleIndex == cycleIndex }
    }

    func getLogsForPhase(_ phase: String) -> [HeartRateLogData] {
        return currentSessionLogs.filter { $0.phase == phase }
    }
}

// SetRecord拡張 - 心拍数統計のみを使用
extension SetRecord {
    var heartRateLogs: [HeartRateLogData] {
        // セッションマネージャーから現在のログを取得
        let logs = HeartRateLogManager.shared.getLogsForCycle(Int(self.cycleIndex))
        return logs.filter { log in
            guard let startAt = self.startAt else { return false }
            if let endAt = self.endAt {
                return log.timestamp >= startAt && log.timestamp <= endAt
            }
            return log.timestamp >= startAt
        }
    }

    // 心拍数統計を計算
    func calculateHeartRateStats(from logs: [HeartRateLogData]) {
        guard !logs.isEmpty else { return }

        let heartRates = logs.map { $0.heartRate }
        self.hrAvg = heartRates.reduce(0, +) / Double(heartRates.count)
        self.hrMax = heartRates.max() ?? 0
        self.hrMin = heartRates.min() ?? 0

        // 勾配計算（時系列データから）
        if logs.count >= 2 {
            let firstRate = logs.first?.heartRate ?? 0
            let lastRate = logs.last?.heartRate ?? 0
            let timeInterval = logs.last?.timestamp.timeIntervalSince(logs.first?.timestamp ?? Date()) ?? 1
            self.hrSlopeAvg = (lastRate - firstRate) / max(timeInterval / 60, 1) // bpm/分
        }
    }
}

// Session拡張 - セッション全体の心拍数統計
extension Session {
    var allHeartRateLogs: [HeartRateLogData] {
        // セッション期間内のログを取得
        guard let startedAt = self.startedAt else { return [] }

        let allLogs = HeartRateLogManager.shared.currentSessionLogs
        let endedAt = self.endedAt ?? Date()

        return allLogs.filter { log in
            log.timestamp >= startedAt && log.timestamp <= endedAt
        }.sorted { $0.timestamp < $1.timestamp }
    }

    var heartRateStatistics: (min: Double, max: Double, avg: Double)? {
        // SetRecordから統計を集計
        guard let setRecords = self.setRecords?.allObjects as? [SetRecord] else { return nil }

        let validRecords = setRecords.filter { $0.hrAvg > 0 }
        guard !validRecords.isEmpty else { return nil }

        let avgRates = validRecords.map { $0.hrAvg }
        let maxRates = validRecords.map { $0.hrMax }
        let minRates = validRecords.map { $0.hrMin }.filter { $0 > 0 }

        return (
            min: minRates.min() ?? 0,
            max: maxRates.max() ?? 0,
            avg: avgRates.reduce(0, +) / Double(avgRates.count)
        )
    }

    // エクスポート用の心拍数ログを生成
    func generateHeartRateLogs() -> [HeartRateLogData] {
        guard let setRecords = self.setRecords?.allObjects as? [SetRecord] else { return [] }

        var logs: [HeartRateLogData] = []

        for record in setRecords.sorted(by: { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }) {
            guard let startAt = record.startAt,
                  let phase = record.phase else { continue }

            // 各レコードの平均心拍数から仮想的なログを生成
            if record.hrAvg > 0 {
                // 開始時点のログ
                logs.append(HeartRateLogData(
                    timestamp: startAt,
                    heartRate: record.hrMin > 0 ? record.hrMin : record.hrAvg,
                    phase: phase,
                    cycleIndex: Int(record.cycleIndex)
                ))

                // 中間点のログ（ピーク）
                if let endAt = record.endAt {
                    let midTime = startAt.addingTimeInterval(endAt.timeIntervalSince(startAt) / 2)
                    logs.append(HeartRateLogData(
                        timestamp: midTime,
                        heartRate: record.hrMax,
                        phase: phase,
                        cycleIndex: Int(record.cycleIndex)
                    ))

                    // 終了時点のログ
                    logs.append(HeartRateLogData(
                        timestamp: endAt,
                        heartRate: record.hrAvg,
                        phase: phase,
                        cycleIndex: Int(record.cycleIndex)
                    ))
                }
            }
        }

        return logs.sorted { $0.timestamp < $1.timestamp }
    }
}