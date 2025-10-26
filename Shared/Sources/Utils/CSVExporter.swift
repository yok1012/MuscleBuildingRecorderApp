import Foundation

struct CSVExporter {
    static func export(session: Session?, records: [SetRecord]) -> String {
        var csv = "Timestamp,Phase,Category,Exercise,Load,Reps,Note,HR Avg,HR Max,HR Min,HR Slope,Duration\n"

        let sortedRecords = records.sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }

        for record in sortedRecords {
            let timestamp = record.startAt?.ISO8601Format() ?? ""
            let phase = record.phase ?? ""
            let category = record.category ?? ""
            let exercise = record.name ?? ""
            let load = String(format: "%.1f", record.load)
            let reps = String(format: "%.0f", record.reps)
            let note = record.note?.replacingOccurrences(of: ",", with: ";") ?? ""
            let hrAvg = String(format: "%.0f", record.hrAvg)
            let hrMax = String(format: "%.0f", record.hrMax)
            let hrMin = String(format: "%.0f", record.hrMin)
            let hrSlope = String(format: "%.1f", record.hrSlopeAvg)

            let duration: String
            if let start = record.startAt, let end = record.endAt {
                let seconds = Int(end.timeIntervalSince(start))
                duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
            } else {
                duration = ""
            }

            csv += "\(timestamp),\(phase),\(category),\(exercise),\(load),\(reps),\(note),\(hrAvg),\(hrMax),\(hrMin),\(hrSlope),\(duration)\n"
        }

        if let session = session {
            csv += "\n\nSession Summary\n"
            csv += "Start Time,End Time,Total Work (sec),Total Rest (sec),Total Volume\n"
            csv += "\(session.startedAt?.ISO8601Format() ?? ""),\(session.endedAt?.ISO8601Format() ?? ""),\(session.totalWorkSec),\(session.totalRestSec),\(session.totalVolume)\n"
        }

        return csv
    }
}