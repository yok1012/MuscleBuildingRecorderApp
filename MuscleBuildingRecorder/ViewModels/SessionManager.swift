import Foundation
import Combine
import CoreData
import WatchConnectivity

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentPhase: WorkoutPhase = .idle
    @Published var phaseStartTime: Date?
    @Published var elapsedTimeString: String = "00:00"
    @Published var elapsedTime: TimeInterval = 0
    @Published var totalWorkTime: TimeInterval = 0
    @Published var totalRestTime: TimeInterval = 0
    @Published var currentSession: Session?
    @Published var currentSetRecord: SetRecord?
    @Published var lastCompletedSession: Session?
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
    private var sessionStartTime: Date?

    private let dataController = DataController.shared
    private let heartRateManager = HeartRateManager.shared
    private let watchConnectivity = WatchConnectivityService.shared
    private let heartRateLogManager = HeartRateLogManager.shared
    private let sensorLogManager = SensorLogManager.shared
    private var heartRateCancellable: AnyCancellable?
    private var sessionSensorData: [[String: Any]] = []  // セッション中のセンサーデータ

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
        print("SessionManager: 🎬 startSession() called")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")
        print("SessionManager: Current thread: \(Thread.current)")

        guard currentPhase == .idle else {
            print("SessionManager: ⚠️ startSession() ignored - already in \(currentPhase.rawValue) phase")
            return
        }

        print("SessionManager: ✅ Starting new session...")

        // Clear previous session result when starting new session
        lastCompletedSession = nil

        currentSession = dataController.createSession()
        currentPhase = .work
        phaseStartTime = Date()
        sessionStartTime = Date()
        cycleIndex = 0
        totalWorkTime = 0
        totalRestTime = 0
        elapsedTime = 0
        startTimer()

        // 心拍数ログの記録を開始
        heartRateLogManager.startNewSession()

        // センサーデータをクリア
        sessionSensorData.removeAll()

        // Watchアプリを起動してワークアウト開始を通知
        watchConnectivity.wakeUpWatch()
        watchConnectivity.startWatchWorkout()
    }

    // Watchからの時間同期付きセッション開始
    func startSessionWithTimeSync(totalWorkTime: TimeInterval, totalRestTime: TimeInterval) {
        print("SessionManager: 🎬 startSessionWithTimeSync() called")
        print("SessionManager: Synced times - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")

        guard currentPhase == .idle else {
            print("SessionManager: ⚠️ Session already active, syncing times instead")
            syncTimeFromWatch(totalWorkTime: totalWorkTime, totalRestTime: totalRestTime)
            return
        }

        // 通常のセッション開始処理
        startSession()

        // Watchからの時間データで上書き
        self.totalWorkTime = totalWorkTime
        self.totalRestTime = totalRestTime
        self.elapsedTime = totalWorkTime + totalRestTime

        print("SessionManager: ✅ Session started with Watch time sync")
    }

    // Watchからの時間データ同期
    func syncTimeFromWatch(totalWorkTime: TimeInterval, totalRestTime: TimeInterval) {
        print("SessionManager: 🔄 syncTimeFromWatch() called")
        print("SessionManager: Current - Work: \(self.totalWorkTime)s, Rest: \(self.totalRestTime)s")
        print("SessionManager: Watch - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")

        // Watchの時間データで更新
        self.totalWorkTime = totalWorkTime
        self.totalRestTime = totalRestTime
        self.elapsedTime = totalWorkTime + totalRestTime

        // 表示用文字列も更新
        updateElapsedTimeString()

        print("SessionManager: ✅ Times synced from Watch")

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
        print("SessionManager: 🔄 togglePhase() called")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")
        print("SessionManager: Current thread: \(Thread.current)")

        guard currentPhase != .idle else {
            print("SessionManager: 🚀 togglePhase() starting new session from idle")
            startSession()
            return
        }

        print("SessionManager: ✅ Toggling phase from \(currentPhase.rawValue)...")

        completeCurrentSetRecord()

        let newPhase: WorkoutPhase = currentPhase == .work ? .rest : .work

        // サイクルインデックスの更新（rest→workの遷移時）
        if currentPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        currentPhase = newPhase
        phaseStartTime = Date()

        // Watchにフェーズ変更を通知（改善版：フェーズとサイクルを通知）
        watchConnectivity.sendPhaseChange(phase: newPhase.rawValue, cycleIndex: cycleIndex)

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
        print("SessionManager: 🛑 endSession() called")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")
        print("SessionManager: Current thread: \(Thread.current)")

        timer?.invalidate()
        timer = nil
        print("SessionManager: Timer invalidated")

        if let record = currentSetRecord {
            completeCurrentSetRecord()
        }

        if let session = currentSession {
            session.endedAt = Date()
            session.totalWorkSec = Int32(totalWorkTime)
            session.totalRestSec = Int32(totalRestTime)
            session.totalVolume = calculateTotalVolume()

            // 心拍数ログを保存
            let heartRateLogs = heartRateLogManager.currentSessionLogs

            dataController.save()

            // セッションデータを保持（リザルト画面で表示するため）
            lastCompletedSession = session
        }

        // Watchにワークアウト終了を通知
        watchConnectivity.stopWatchWorkout()

        // リセット前に合計時間を記録
        let finalWorkTime = totalWorkTime
        let finalRestTime = totalRestTime

        resetSession()

        // リザルト表示用に時間を復元
        totalWorkTime = finalWorkTime
        totalRestTime = finalRestTime
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
                totalWorkTime = workTimeAccumulated
            } else {
                restTimeAccumulated += elapsed
                totalRestTime = restTimeAccumulated
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

        let phaseElapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(phaseElapsed) / 60
        let seconds = Int(phaseElapsed) % 60
        elapsedTimeString = String(format: "%02d:%02d", minutes, seconds)

        // 総経過時間を更新
        if let sessionStart = sessionStartTime {
            elapsedTime = Date().timeIntervalSince(sessionStart)
        }

        // フェーズ別の合計時間を更新
        if currentPhase == .work {
            totalWorkTime = workTimeAccumulated + phaseElapsed
        } else if currentPhase == .rest {
            totalRestTime = restTimeAccumulated + phaseElapsed
        }
    }

    // 経過時間の表示文字列を更新
    private func updateElapsedTimeString() {
        let totalSeconds = Int(elapsedTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        elapsedTimeString = String(format: "%02d:%02d", minutes, seconds)
    }

    private func resetSession() {
        currentPhase = .idle
        phaseStartTime = nil
        sessionStartTime = nil
        elapsedTimeString = "00:00"
        elapsedTime = 0
        totalWorkTime = 0
        totalRestTime = 0
        currentSession = nil
        currentSetRecord = nil
        cycleIndex = 0
        workTimeAccumulated = 0
        restTimeAccumulated = 0

        // メモリクリーンアップ
        sessionSensorData.removeAll()
        heartRateLogManager.clearLogs()
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

    // センサーデータを取得（セッション期間中のデータ）
    func getSensorDataForCurrentSession() -> String {
        guard let startTime = sessionStartTime else { return "[]" }

        // SensorLogManagerから現在の日付のデータを取得
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        // 加速度データファイルのパスを取得
        let accelUrl = sensorLogManager.logDirectory.appendingPathComponent("accelerometer_\(dateString).csv")
        let gyroUrl = sensorLogManager.logDirectory.appendingPathComponent("gyroscope_\(dateString).csv")

        var sensorData: [[String: Any]] = []

        // 加速度データを読み込み
        if FileManager.default.fileExists(atPath: accelUrl.path) {
            do {
                let csvContent = try String(contentsOf: accelUrl, encoding: .utf8)
                let lines = csvContent.components(separatedBy: .newlines)

                for (index, line) in lines.enumerated() {
                    if index == 0 || line.isEmpty { continue } // ヘッダーをスキップ

                    let components = line.components(separatedBy: ",")
                    if components.count >= 4 {
                        if let timestamp = Int64(components[0]),
                           let ax = Double(components[1]),
                           let ay = Double(components[2]),
                           let az = Double(components[3]) {

                            let sampleTime = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)

                            // セッション期間中のデータのみ
                            if sampleTime >= startTime {
                                sensorData.append([
                                    "timestamp": timestamp,
                                    "accelX": ax,
                                    "accelY": ay,
                                    "accelZ": az
                                ])
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read accelerometer data: \(error)")
            }
        }

        // ジャイロデータを追加（同じtimestampのデータに追加）
        if FileManager.default.fileExists(atPath: gyroUrl.path) {
            do {
                let csvContent = try String(contentsOf: gyroUrl, encoding: .utf8)
                let lines = csvContent.components(separatedBy: .newlines)

                for (index, line) in lines.enumerated() {
                    if index == 0 || line.isEmpty { continue }

                    let components = line.components(separatedBy: ",")
                    if components.count >= 4 {
                        if let timestamp = Int64(components[0]),
                           let gx = Double(components[1]),
                           let gy = Double(components[2]),
                           let gz = Double(components[3]) {

                            // 既存のデータに追加
                            if let index = sensorData.firstIndex(where: { $0["timestamp"] as? Int64 == timestamp }) {
                                sensorData[index]["gyroX"] = gx
                                sensorData[index]["gyroY"] = gy
                                sensorData[index]["gyroZ"] = gz
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read gyroscope data: \(error)")
            }
        }

        // JSON文字列に変換
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sensorData, options: [])
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            print("Failed to serialize sensor data: \(error)")
            return "[]"
        }
    }
}