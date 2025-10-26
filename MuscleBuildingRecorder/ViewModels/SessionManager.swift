import Foundation
import Combine
import CoreData
import WatchConnectivity

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentPhase: WorkoutPhase = .idle
    @Published var phaseStartTime: Date?
    @Published var elapsedTimeString: String = "00:00"
    @Published var currentSession: Session?
    @Published var currentSetRecord: SetRecord?
    @Published var cycleIndex: Int = 0

    @Published var selectedCategory: String = "胸"
    @Published var selectedExercise: String = "ベンチプレス"
    @Published var currentLoad: Double = 40.0
    @Published var currentReps: Double = 10.0
    @Published var currentNote: String = ""
    @Published var loadUnit: String = "kg"
    @Published var repsUnit: String = "回"

    private var timer: Timer?
    private var workTimeAccumulated: TimeInterval = 0
    private var restTimeAccumulated: TimeInterval = 0

    private let dataController = DataController.shared
    private let heartRateManager = HeartRateManager.shared
    private let watchConnectivity = WatchConnectivityService.shared
    private let heartRateLogManager = HeartRateLogManager.shared
    private var heartRateCancellable: AnyCancellable?

    private init() {
        loadDefaultExerciseValues()
        setupHeartRateLogging()
    }

    private func setupHeartRateLogging() {
        // HeartRateManagerからの心拍数更新を購読
        heartRateCancellable = heartRateManager.$currentHeartRate
            .sink { [weak self] heartRate in
                guard let self = self,
                      self.currentPhase != .idle,
                      heartRate > 0 else { return }

                // 心拍数ログを記録
                self.heartRateLogManager.addLog(
                    heartRate: heartRate,
                    phase: self.currentPhase.rawValue.capitalized,
                    cycleIndex: self.cycleIndex
                )
            }
    }

    func startSession() {
        guard currentPhase == .idle else { return }

        currentSession = dataController.createSession()
        currentPhase = .work
        phaseStartTime = Date()
        cycleIndex = 0
        startTimer()

        // 心拍数ログの記録を開始
        heartRateLogManager.startNewSession()

        // Watchにワークアウト開始を通知
        watchConnectivity.startWatchWorkout()

        let record = dataController.createSetRecord(
            sessionId: currentSession!.id!,
            phase: .work,
            cycleIndex: cycleIndex
        )
        record.category = selectedCategory
        record.name = selectedExercise
        record.load = currentLoad
        record.reps = currentReps
        record.session = currentSession // セッションとの関連付けを追加
        currentSetRecord = record

        // Core Dataに即座に保存
        dataController.save()
    }

    func togglePhase() {
        guard currentPhase != .idle else {
            startSession()
            return
        }

        completeCurrentSetRecord()

        let newPhase: WorkoutPhase = currentPhase == .work ? .rest : .work

        // Watchにフェーズ変更を通知
        if newPhase == .rest {
            watchConnectivity.pauseWatchWorkout()
        } else {
            watchConnectivity.resumeWatchWorkout()
        }

        if currentPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        currentPhase = newPhase
        phaseStartTime = Date()

        let record = dataController.createSetRecord(
            sessionId: currentSession!.id!,
            phase: newPhase,
            cycleIndex: cycleIndex
        )
        record.category = selectedCategory
        record.name = selectedExercise
        record.load = currentLoad
        record.reps = currentReps
        record.note = currentNote
        record.session = currentSession // セッションとの関連付けを追加
        currentSetRecord = record

        // Core Dataに即座に保存
        dataController.save()
    }

    func saveCurrentCycle() {
        guard let record = currentSetRecord, currentPhase == .rest else { return }

        completeCurrentSetRecord()
        dataController.save()

        currentNote = ""
    }

    func endSession() {
        timer?.invalidate()
        timer = nil

        if let record = currentSetRecord {
            completeCurrentSetRecord()
        }

        if let session = currentSession {
            session.endedAt = Date()
            session.totalWorkSec = Int32(workTimeAccumulated)
            session.totalRestSec = Int32(restTimeAccumulated)
            session.totalVolume = calculateTotalVolume()
            dataController.save()
        }

        // Watchにワークアウト終了を通知
        watchConnectivity.stopWatchWorkout()

        resetSession()
    }

    private func completeCurrentSetRecord() {
        guard let record = currentSetRecord else { return }

        record.endAt = Date()
        record.note = currentNote

        let hrStats = heartRateManager.getHeartRateStats()
        record.hrAvg = hrStats.avg
        record.hrMax = hrStats.max
        record.hrMin = hrStats.min
        record.hrSlopeAvg = heartRateManager.heartRateSlope

        if let startTime = phaseStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if currentPhase == .work {
                workTimeAccumulated += elapsed
            } else {
                restTimeAccumulated += elapsed
            }
        }

        dataController.save()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateElapsedTime()
        }
    }

    private func updateElapsedTime() {
        guard let startTime = phaseStartTime else {
            elapsedTimeString = "00:00"
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTimeString = String(format: "%02d:%02d", minutes, seconds)
    }

    private func resetSession() {
        currentPhase = .idle
        phaseStartTime = nil
        elapsedTimeString = "00:00"
        currentSession = nil
        currentSetRecord = nil
        cycleIndex = 0
        workTimeAccumulated = 0
        restTimeAccumulated = 0
    }

    private func calculateTotalVolume() -> Double {
        guard let session = currentSession,
              let records = session.setRecords?.allObjects as? [SetRecord] else { return 0 }

        return records.reduce(0) { $0 + ($1.load * $1.reps) }
    }

    func loadDefaultExerciseValues() {
        let request = NSFetchRequest<ExerciseMaster>(entityName: "ExerciseMaster")
        request.predicate = NSPredicate(
            format: "category == %@ AND name == %@",
            selectedCategory,
            selectedExercise
        )

        do {
            let exercises = try dataController.container.viewContext.fetch(request)
            if let exercise = exercises.first {
                currentLoad = exercise.defaultLoad
                currentReps = exercise.defaultReps
                loadUnit = exercise.loadUnit ?? "kg"
                repsUnit = exercise.repsUnit ?? "回"
            }
        } catch {
            print("Failed to load exercise defaults: \(error)")
        }
    }

    func getAvailableCategories() -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "ExerciseMaster")
        request.propertiesToFetch = ["category"]
        request.returnsDistinctResults = true
        request.resultType = .dictionaryResultType

        do {
            let results = try dataController.container.viewContext.fetch(request)
            return results.compactMap { $0["category"] as? String }.sorted()
        } catch {
            print("Failed to fetch categories: \(error)")
            return []
        }
    }

    func getExercises(for category: String) -> [String] {
        let request = NSFetchRequest<ExerciseMaster>(entityName: "ExerciseMaster")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let exercises = try dataController.container.viewContext.fetch(request)
            return exercises.compactMap { $0.name }
        } catch {
            print("Failed to fetch exercises: \(error)")
            return []
        }
    }
}