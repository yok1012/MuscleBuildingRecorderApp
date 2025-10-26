import Foundation
import CoreData

class JSONExporter {
    static func export(sessions: [Session]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = sessions.map { session in
            var sessionData = SessionData(from: session)
            if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
                // SetRecordsを時系列でソート
                let sortedRecords = setRecords.sorted { ($0.startAt ?? Date.distantPast) < ($1.startAt ?? Date.distantPast) }
                sessionData.records = sortedRecords.map { RecordData(from: $0) }
            }
            return sessionData
        }

        do {
            let jsonData = try encoder.encode(exportData)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            print("Failed to encode JSON: \(error)")
            // エラー情報を含むJSONを返す
            return """
            {
              "error": "Failed to encode data",
              "message": "\(error.localizedDescription)",
              "sessions_count": \(sessions.count)
            }
            """
        }
    }

    // 単一セッションのエクスポート
    static func exportSingleSession(_ session: Session) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var sessionData = SessionData(from: session)
        if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
            let sortedRecords = setRecords.sorted { ($0.startAt ?? Date.distantPast) < ($1.startAt ?? Date.distantPast) }
            sessionData.records = sortedRecords.map { RecordData(from: $0) }
        }

        do {
            let jsonData = try encoder.encode(sessionData)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            print("Failed to encode JSON: \(error)")
            return "{}"
        }
    }

    // 統計情報を含む詳細エクスポート
    static func exportWithStatistics(sessions: [Session]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = ExportDataWithStatistics(sessions: sessions)

        do {
            let jsonData = try encoder.encode(exportData)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            print("Failed to encode JSON with statistics: \(error)")
            return "{}"
        }
    }
}

struct SessionData: Codable {
    let id: String
    let startedAt: Date?
    let endedAt: Date?
    let totalWorkSec: Int
    let totalRestSec: Int
    let totalVolume: Double
    let totalDurationSec: Int
    let setCount: Int
    let statistics: SessionStatistics
    var records: [RecordData] = []

    init(from session: Session) {
        self.id = session.id?.uuidString ?? ""
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.totalWorkSec = Int(session.totalWorkSec)
        self.totalRestSec = Int(session.totalRestSec)
        self.totalVolume = session.totalVolume
        self.totalDurationSec = Int(session.totalWorkSec + session.totalRestSec)
        self.setCount = session.setRecords?.count ?? 0
        self.statistics = SessionStatistics(from: session)
    }
}

struct SessionStatistics: Codable {
    let avgHeartRate: Double
    let maxHeartRate: Double
    let minHeartRate: Double
    let workSets: Int
    let restSets: Int
    let categories: [String]
    let exercises: [String]

    init(from session: Session) {
        guard let setRecords = session.setRecords?.allObjects as? [SetRecord], !setRecords.isEmpty else {
            self.avgHeartRate = 0
            self.maxHeartRate = 0
            self.minHeartRate = 0
            self.workSets = 0
            self.restSets = 0
            self.categories = []
            self.exercises = []
            return
        }

        // 心拍数統計
        let hrValues = setRecords.filter { $0.hrAvg > 0 }.map { $0.hrAvg }
        self.avgHeartRate = hrValues.isEmpty ? 0 : hrValues.reduce(0, +) / Double(hrValues.count)
        self.maxHeartRate = setRecords.map { $0.hrMax }.max() ?? 0
        self.minHeartRate = setRecords.filter { $0.hrMin > 0 }.map { $0.hrMin }.min() ?? 0

        // フェーズ別カウント
        self.workSets = setRecords.filter { $0.phase == "Work" }.count
        self.restSets = setRecords.filter { $0.phase == "Rest" }.count

        // カテゴリーと種目のユニークリスト
        let categoriesSet = Set(setRecords.compactMap { $0.category }.filter { !$0.isEmpty })
        self.categories = Array(categoriesSet).sorted()

        let exercisesSet = Set(setRecords.compactMap { $0.name }.filter { !$0.isEmpty })
        self.exercises = Array(exercisesSet).sorted()
    }
}

struct RecordData: Codable {
    let id: String
    let sessionId: String
    let cycleIndex: Int
    let phase: String
    let startAt: Date?
    let endAt: Date?
    let category: String
    let exercise: String
    let load: Double
    let reps: Double
    let note: String
    let heartRate: HeartRateData
    let durationSec: Int?

    init(from record: SetRecord) {
        self.id = record.id?.uuidString ?? ""
        self.sessionId = record.sessionId?.uuidString ?? ""
        self.cycleIndex = Int(record.cycleIndex)
        self.phase = record.phase ?? ""
        self.startAt = record.startAt
        self.endAt = record.endAt
        self.category = record.category ?? ""
        self.exercise = record.name ?? ""
        self.load = record.load
        self.reps = record.reps
        self.note = record.note ?? ""
        self.heartRate = HeartRateData(
            avg: record.hrAvg,
            max: record.hrMax,
            min: record.hrMin,
            slope: record.hrSlopeAvg
        )

        if let start = record.startAt, let end = record.endAt {
            self.durationSec = Int(end.timeIntervalSince(start))
        } else {
            self.durationSec = nil
        }
    }
}

struct HeartRateData: Codable {
    let avg: Double
    let max: Double
    let min: Double
    let slope: Double
}

struct ExportDataWithStatistics: Codable {
    let exportDate: Date
    let totalSessions: Int
    let totalWorkoutTime: Int
    let totalVolume: Double
    let overallStatistics: OverallStatistics
    let sessions: [SessionData]

    init(sessions: [Session]) {
        self.exportDate = Date()
        self.totalSessions = sessions.count
        self.totalWorkoutTime = sessions.reduce(0) { $0 + Int($1.totalWorkSec + $1.totalRestSec) }
        self.totalVolume = sessions.reduce(0) { $0 + $1.totalVolume }
        self.overallStatistics = OverallStatistics(from: sessions)
        self.sessions = sessions.map { session in
            var sessionData = SessionData(from: session)
            if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
                let sortedRecords = setRecords.sorted { ($0.startAt ?? Date.distantPast) < ($1.startAt ?? Date.distantPast) }
                sessionData.records = sortedRecords.map { RecordData(from: $0) }
            }
            return sessionData
        }
    }
}

struct OverallStatistics: Codable {
    let avgSessionDuration: Double
    let avgHeartRate: Double
    let maxHeartRate: Double
    let totalSets: Int
    let uniqueExercises: Int

    init(from sessions: [Session]) {
        let sessionCount = sessions.count

        // 平均セッション時間
        if sessionCount > 0 {
            let totalTime = sessions.reduce(0) { $0 + Int($1.totalWorkSec + $1.totalRestSec) }
            self.avgSessionDuration = Double(totalTime) / Double(sessionCount)
        } else {
            self.avgSessionDuration = 0
        }

        // 全体の心拍数統計と種目統計
        var allHeartRates: [Double] = []
        var maxHr: Double = 0
        var allExercises = Set<String>()
        var totalSetsCount = 0

        for session in sessions {
            if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
                totalSetsCount += setRecords.count

                for record in setRecords {
                    if record.hrAvg > 0 {
                        allHeartRates.append(record.hrAvg)
                    }
                    if record.hrMax > maxHr {
                        maxHr = record.hrMax
                    }
                    if let name = record.name, !name.isEmpty {
                        allExercises.insert(name)
                    }
                }
            }
        }

        self.avgHeartRate = allHeartRates.isEmpty ? 0 : allHeartRates.reduce(0, +) / Double(allHeartRates.count)
        self.maxHeartRate = maxHr
        self.totalSets = totalSetsCount
        self.uniqueExercises = allExercises.count
    }
}