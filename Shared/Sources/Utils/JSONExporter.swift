import Foundation

struct JSONExporter {
    static func export(session: Session?, records: [SetRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = SessionExportData(
            session: session != nil ? SessionData(from: session!) : nil,
            records: records.map { RecordData(from: $0) }
        )

        do {
            let jsonData = try encoder.encode(exportData)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            print("Failed to encode JSON: \(error)")
            return "{}"
        }
    }
}

struct SessionExportData: Codable {
    let session: SessionData?
    let records: [RecordData]
}

struct SessionData: Codable {
    let id: String
    let startedAt: Date?
    let endedAt: Date?
    let totalWorkSec: Int
    let totalRestSec: Int
    let totalVolume: Double

    init(from session: Session) {
        self.id = session.id?.uuidString ?? ""
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.totalWorkSec = Int(session.totalWorkSec)
        self.totalRestSec = Int(session.totalRestSec)
        self.totalVolume = session.totalVolume
    }
}

struct RecordData: Codable {
    let id: String
    let cycleIndex: Int
    let phase: String
    let startAt: Date?
    let endAt: Date?
    let category: String
    let exercise: String
    let load: Double
    let reps: Double
    let note: String
    let hrAvg: Double
    let hrMax: Double
    let hrMin: Double
    let hrSlope: Double
    let duration: Int?

    init(from record: SetRecord) {
        self.id = record.id?.uuidString ?? ""
        self.cycleIndex = Int(record.cycleIndex)
        self.phase = record.phase ?? ""
        self.startAt = record.startAt
        self.endAt = record.endAt
        self.category = record.category ?? ""
        self.exercise = record.name ?? ""
        self.load = record.load
        self.reps = record.reps
        self.note = record.note ?? ""
        self.hrAvg = record.hrAvg
        self.hrMax = record.hrMax
        self.hrMin = record.hrMin
        self.hrSlope = record.hrSlopeAvg

        if let start = record.startAt, let end = record.endAt {
            self.duration = Int(end.timeIntervalSince(start))
        } else {
            self.duration = nil
        }
    }
}