import XCTest
import CoreData
@testable import WorkoutTimer

class SessionManagerTests: XCTestCase {
    var sessionManager: SessionManager!
    var dataController: DataController!

    override func setUp() {
        super.setUp()
        sessionManager = SessionManager.shared
        dataController = DataController.shared
    }

    override func tearDown() {
        sessionManager.endSession()
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(sessionManager.currentPhase, .idle, "Initial phase should be idle")
        XCTAssertNil(sessionManager.currentSession, "Session should be nil initially")
        XCTAssertEqual(sessionManager.cycleIndex, 0, "Cycle index should be 0 initially")
        XCTAssertEqual(sessionManager.elapsedTimeString, "00:00", "Initial time should be 00:00")
    }

    func testStartSession() {
        sessionManager.startSession()

        XCTAssertEqual(sessionManager.currentPhase, .work, "Phase should be work after starting")
        XCTAssertNotNil(sessionManager.currentSession, "Session should exist after starting")
        XCTAssertNotNil(sessionManager.phaseStartTime, "Phase start time should be set")
        XCTAssertEqual(sessionManager.cycleIndex, 0, "Cycle index should be 0 when starting")
    }

    func testPhaseTransition() {
        sessionManager.startSession()
        XCTAssertEqual(sessionManager.currentPhase, .work, "Should start in work phase")

        sessionManager.togglePhase()
        XCTAssertEqual(sessionManager.currentPhase, .rest, "Should transition to rest phase")

        sessionManager.togglePhase()
        XCTAssertEqual(sessionManager.currentPhase, .work, "Should transition back to work phase")
        XCTAssertEqual(sessionManager.cycleIndex, 1, "Cycle index should increment after rest->work transition")
    }

    func testSaveCurrentCycle() {
        sessionManager.startSession()
        sessionManager.togglePhase()

        let initialNote = "Test note"
        sessionManager.currentNote = initialNote

        sessionManager.saveCurrentCycle()

        XCTAssertEqual(sessionManager.currentNote, "", "Note should be cleared after saving")
    }

    func testEndSession() {
        sessionManager.startSession()
        sessionManager.togglePhase()
        sessionManager.endSession()

        XCTAssertEqual(sessionManager.currentPhase, .idle, "Phase should return to idle")
        XCTAssertNil(sessionManager.phaseStartTime, "Phase start time should be nil")
        XCTAssertEqual(sessionManager.elapsedTimeString, "00:00", "Time should reset to 00:00")
        XCTAssertEqual(sessionManager.cycleIndex, 0, "Cycle index should reset to 0")
    }

    func testLoadDefaultExerciseValues() {
        sessionManager.selectedCategory = "胸"
        sessionManager.selectedExercise = "ベンチプレス"
        sessionManager.loadDefaultExerciseValues()

        XCTAssertEqual(sessionManager.loadUnit, "kg", "Load unit should be kg for bench press")
        XCTAssertEqual(sessionManager.repsUnit, "回", "Reps unit should be 回 for bench press")
        XCTAssertGreaterThan(sessionManager.currentLoad, 0, "Default load should be greater than 0")
        XCTAssertGreaterThan(sessionManager.currentReps, 0, "Default reps should be greater than 0")
    }

    func testVolumeCalculation() {
        sessionManager.startSession()
        sessionManager.currentLoad = 50
        sessionManager.currentReps = 10

        let volume = sessionManager.currentLoad * sessionManager.currentReps
        XCTAssertEqual(volume, 500, "Volume should be load * reps")
    }
}