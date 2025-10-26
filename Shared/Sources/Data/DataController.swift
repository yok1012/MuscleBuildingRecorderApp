import CoreData
import Foundation

class DataController: ObservableObject {
    static let shared = DataController()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "WorkoutModel")

        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error.localizedDescription)")
            }
        }
    }

    func loadInitialData() {
        let context = container.viewContext
        let request = NSFetchRequest<ExerciseMaster>(entityName: "ExerciseMaster")

        do {
            let count = try context.count(for: request)
            if count == 0 {
                loadExerciseDefaults()
            }
        } catch {
            print("Failed to fetch exercise count: \(error)")
        }
    }

    private func loadExerciseDefaults() {
        let exercises: [[String: Any]] = [
            ["category": "胸", "name": "ベンチプレス", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 40.0, "defaultReps": 10.0],
            ["category": "胸", "name": "ダンベルフライ", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 12.0, "defaultReps": 12.0],
            ["category": "胸", "name": "プッシュアップ", "loadUnit": "レベル", "repsUnit": "回", "defaultLoad": 1.0, "defaultReps": 20.0],
            ["category": "背中", "name": "デッドリフト", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 60.0, "defaultReps": 8.0],
            ["category": "背中", "name": "ラットプルダウン", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 40.0, "defaultReps": 10.0],
            ["category": "脚", "name": "スクワット", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 60.0, "defaultReps": 8.0],
            ["category": "脚", "name": "レッグプレス", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 80.0, "defaultReps": 10.0],
            ["category": "肩", "name": "ショルダープレス", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 20.0, "defaultReps": 10.0],
            ["category": "肩", "name": "サイドレイズ", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 5.0, "defaultReps": 15.0],
            ["category": "腕", "name": "バーベルカール", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 20.0, "defaultReps": 12.0],
            ["category": "腕", "name": "トライセプスエクステンション", "loadUnit": "kg", "repsUnit": "回", "defaultLoad": 15.0, "defaultReps": 12.0],
            ["category": "体幹", "name": "プランク", "loadUnit": "秒", "repsUnit": "セット", "defaultLoad": 60.0, "defaultReps": 3.0],
            ["category": "体幹", "name": "アブローラー", "loadUnit": "レベル", "repsUnit": "回", "defaultLoad": 1.0, "defaultReps": 10.0],
            ["category": "有酸素", "name": "バイク", "loadUnit": "W", "repsUnit": "分", "defaultLoad": 150.0, "defaultReps": 10.0],
            ["category": "有酸素", "name": "トレッドミル", "loadUnit": "km/h", "repsUnit": "分", "defaultLoad": 8.0, "defaultReps": 20.0]
        ]

        let context = container.viewContext

        for exerciseData in exercises {
            let exercise = ExerciseMaster(context: context)
            exercise.id = UUID()
            exercise.category = exerciseData["category"] as? String
            exercise.name = exerciseData["name"] as? String
            exercise.loadUnit = exerciseData["loadUnit"] as? String
            exercise.repsUnit = exerciseData["repsUnit"] as? String
            exercise.defaultLoad = exerciseData["defaultLoad"] as? Double ?? 0
            exercise.defaultReps = exerciseData["defaultReps"] as? Double ?? 0
            exercise.isActive = true
        }

        save()
    }

    func createSession() -> Session {
        let context = container.viewContext
        let session = Session(context: context)
        session.id = UUID()
        session.startedAt = Date()
        session.totalWorkSec = 0
        session.totalRestSec = 0
        session.totalVolume = 0
        return session
    }

    func createSetRecord(sessionId: UUID, phase: WorkoutPhase, cycleIndex: Int) -> SetRecord {
        let context = container.viewContext
        let record = SetRecord(context: context)
        record.id = UUID()
        record.sessionId = sessionId
        record.phase = phase.rawValue
        record.cycleIndex = Int32(cycleIndex)
        record.startAt = Date()
        return record
    }
}