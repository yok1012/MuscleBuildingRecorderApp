import XCTest
import CoreData
@testable import WorkoutTimer

class ExportTests: XCTestCase {

    func testCSVExport() {
        let session = createMockSession()
        let records = createMockRecords()

        let csv = CSVExporter.export(session: session, records: records)

        XCTAssertTrue(csv.contains("Timestamp,Phase,Category,Exercise"), "CSV should contain headers")
        XCTAssertTrue(csv.contains("胸"), "CSV should contain category")
        XCTAssertTrue(csv.contains("ベンチプレス"), "CSV should contain exercise name")
        XCTAssertTrue(csv.contains("40.0"), "CSV should contain load value")
        XCTAssertTrue(csv.contains("10"), "CSV should contain reps value")
    }

    func testJSONExport() {
        let session = createMockSession()
        let records = createMockRecords()

        let json = JSONExporter.export(session: session, records: records)

        XCTAssertTrue(json.contains("\"category\" : \"胸\""), "JSON should contain category")
        XCTAssertTrue(json.contains("\"exercise\" : \"ベンチプレス\""), "JSON should contain exercise")
        XCTAssertTrue(json.contains("\"load\" : 40"), "JSON should contain load")
        XCTAssertTrue(json.contains("\"reps\" : 10"), "JSON should contain reps")
        XCTAssertTrue(json.contains("\"phase\" : \"Work\""), "JSON should contain phase")
    }

    func testEmptyExport() {
        let csv = CSVExporter.export(session: nil, records: [])
        XCTAssertTrue(csv.contains("Timestamp"), "CSV should contain headers even when empty")

        let json = JSONExporter.export(session: nil, records: [])
        XCTAssertTrue(json.contains("records"), "JSON should contain records array even when empty")
    }

    private func createMockSession() -> Session {
        let session = Session(context: DataController.shared.container.viewContext)
        session.id = UUID()
        session.startedAt = Date()
        session.endedAt = Date().addingTimeInterval(1800)
        session.totalWorkSec = 900
        session.totalRestSec = 300
        session.totalVolume = 1200
        return session
    }

    private func createMockRecords() -> [SetRecord] {
        var records: [SetRecord] = []

        let workRecord = SetRecord(context: DataController.shared.container.viewContext)
        workRecord.id = UUID()
        workRecord.cycleIndex = 0
        workRecord.phase = "Work"
        workRecord.startAt = Date()
        workRecord.endAt = Date().addingTimeInterval(60)
        workRecord.category = "胸"
        workRecord.name = "ベンチプレス"
        workRecord.load = 40
        workRecord.reps = 10
        workRecord.note = "Good form"
        workRecord.hrAvg = 120
        workRecord.hrMax = 140
        workRecord.hrMin = 100
        workRecord.hrSlopeAvg = 5.5
        records.append(workRecord)

        let restRecord = SetRecord(context: DataController.shared.container.viewContext)
        restRecord.id = UUID()
        restRecord.cycleIndex = 0
        restRecord.phase = "Rest"
        restRecord.startAt = Date().addingTimeInterval(60)
        restRecord.endAt = Date().addingTimeInterval(90)
        restRecord.category = "胸"
        restRecord.name = "ベンチプレス"
        restRecord.load = 40
        restRecord.reps = 10
        restRecord.note = ""
        restRecord.hrAvg = 100
        restRecord.hrMax = 120
        restRecord.hrMin = 90
        restRecord.hrSlopeAvg = -3.2
        records.append(restRecord)

        return records
    }
}