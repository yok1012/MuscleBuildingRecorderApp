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
        
        // 心拍数モニタリングを開始（Watch/iPhone自動選択）
        heartRateManager.startMonitoring()

        // Watchが利用可能な場合のみ、Watchワークアウトを開始
        if watchConnectivity.isWatchConnected {
            print("SessionManager: Watch connected - starting Watch workout")
            watchConnectivity.wakeUpWatch()
            watchConnectivity.startWatchWorkout()
        } else {
            print("SessionManager: Watch not connected - running in iPhone standalone mode")
            // iPhoneスタンドアロンモードで動作
            // 心拍数はHeartRateManagerが自動でiPhone HealthKitから取得
        }
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
    func syncTimeFromWatch(
        totalWorkTime: TimeInterval,
        totalRestTime: TimeInterval,
        currentPhaseIdentifier: String? = nil,
        currentPhaseTime: TimeInterval? = nil,
        completedPhaseIdentifier: String? = nil,
        completedPhaseDuration: TimeInterval? = nil
    ) {
        print("SessionManager: 🔄 syncTimeFromWatch() called")
        print("SessionManager: Current - Work: \(self.totalWorkTime)s, Rest: \(self.totalRestTime)s")
        print("SessionManager: Watch - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")
        if let currentPhaseIdentifier {
            print("SessionManager: Watch current phase identifier: \(currentPhaseIdentifier)")
        }
        if let completedPhaseIdentifier {
            print("SessionManager: Watch previous phase identifier: \(completedPhaseIdentifier)")
        }

        // Watchの時間データで更新
        self.totalWorkTime = totalWorkTime
        self.totalRestTime = totalRestTime
        self.elapsedTime = totalWorkTime + totalRestTime
        self.sessionStartTime = Date().addingTimeInterval(-(totalWorkTime + totalRestTime))

        // 標準ではwatchから送られた累積値と一致させる
        self.workTimeAccumulated = totalWorkTime
        self.restTimeAccumulated = totalRestTime

        let normalizedCompletedPhase = completedPhaseIdentifier.flatMap { phase(from: $0) }
        let normalizedCurrentPhase = currentPhaseIdentifier.flatMap { phase(from: $0) }

        if let completedPhase = normalizedCompletedPhase,
           let completedDuration = completedPhaseDuration,
           completedDuration > 0 {
            switch completedPhase {
            case .work:
                self.workTimeAccumulated = max(totalWorkTime - completedDuration, 0)
            case .rest:
                self.restTimeAccumulated = max(totalRestTime - completedDuration, 0)
            case .idle:
                break
            }
            self.phaseStartTime = Date().addingTimeInterval(-completedDuration)
        } else if normalizedCompletedPhase != nil {
            // フェーズ情報は届いたが時間が不明な場合は二重加算を避けるため直近時刻でリセット
            self.phaseStartTime = Date()
        } else if normalizedCompletedPhase == nil,
                  let phase = normalizedCurrentPhase,
                  let phaseDuration = currentPhaseTime {
            if phase != .idle {
                self.currentPhase = phase
            }
            self.phaseStartTime = Date().addingTimeInterval(-phaseDuration)
        }

        if let phase = normalizedCurrentPhase {
            self.currentPhase = phase
        }

        // 表示用文字列も更新
        updateElapsedTimeString()

        print("SessionManager: ✅ Times synced from Watch")

        // セッションやIDが欠落している場合は補完する（Watchのみで開始されたケースを考慮）
        let shouldEnsureSession = currentPhase != .idle || totalWorkTime > 0 || totalRestTime > 0
        let session = shouldEnsureSession ? ensureActiveSession(startTime: sessionStartTime) : currentSession

        // Watch側で先行して開始されたケースでセットレコードが未生成の場合のみ作成
        if currentSetRecord == nil,
           let session,
           let sessionId = session.id,
           currentPhase != .idle {
            let record = dataController.createSetRecord(
                sessionId: sessionId,
                phase: currentPhase,
                cycleIndex: cycleIndex
            )
            record.category = selectedCategory
            record.name = selectedExercise
            record.load = currentLoad
            record.reps = currentReps
            record.session = session
            currentSetRecord = record

            // Core Dataに即座に保存
            dataController.save()
        }
    }

    func togglePhase() {
        // iPhone UIからの呼び出し用（Watchに通知する）
        togglePhaseInternal(notifyWatch: true)
    }

    /// Watchからのフェーズ変更を適用（Watchには通知しない）
    /// - Parameters:
    ///   - newPhaseIdentifier: 新しいフェーズ ("work" or "rest")
    ///   - previousPhaseIdentifier: 前のフェーズ
    ///   - previousPhaseDuration: 前のフェーズの継続時間
    func applyPhaseChangeFromWatch(
        newPhaseIdentifier: String,
        previousPhaseIdentifier: String?,
        previousPhaseDuration: TimeInterval?
    ) {
        print("SessionManager: 📲 applyPhaseChangeFromWatch() - newPhase: \(newPhaseIdentifier)")

        guard let newPhase = phase(from: newPhaseIdentifier), newPhase != .idle else {
            print("SessionManager: ⚠️ Invalid phase identifier: \(newPhaseIdentifier)")
            return
        }

        // idleの場合はセッション開始
        if currentPhase == .idle {
            print("SessionManager: 🚀 Starting new session from Watch command")
            startSession()
            // セッション開始後、必要に応じてフェーズを設定
            if newPhase != .work {
                applyPhaseInternal(newPhase: newPhase, notifyWatch: false)
            }
            return
        }

        // 既に同じフェーズの場合は何もしない（重複処理防止）
        if currentPhase == newPhase {
            print("SessionManager: ℹ️ Already in phase \(newPhaseIdentifier), skipping")
            return
        }

        applyPhaseInternal(newPhase: newPhase, notifyWatch: false)
    }

    /// フェーズ変更の内部実装
    /// - Parameters:
    ///   - newPhase: 新しいフェーズ
    ///   - notifyWatch: Watchに通知するかどうか（iPhone UIからの操作時はtrue、Watchからの操作時はfalse）
    private func applyPhaseInternal(newPhase: WorkoutPhase, notifyWatch: Bool) {
        let previousPhase = currentPhase
        let now = Date()
        let completedPhaseDuration: TimeInterval
        if let startTime = phaseStartTime {
            completedPhaseDuration = max(now.timeIntervalSince(startTime), 0)
        } else {
            completedPhaseDuration = 0
        }

        completeCurrentSetRecord()

        guard let session = ensureActiveSession(startTime: sessionStartTime),
              let sessionId = session.id else {
            print("SessionManager: ⚠️ applyPhaseInternal() aborted - active session unavailable")
            return
        }

        // サイクルインデックスの更新（rest→workの遷移時）
        if previousPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        currentPhase = newPhase
        phaseStartTime = now

        if let sessionStart = sessionStartTime {
            elapsedTime = now.timeIntervalSince(sessionStart)
            updateElapsedTimeString()
        }

        // Watchに通知（iPhone UIからの操作時のみ）
        if notifyWatch {
            watchConnectivity.sendPhaseChange(
                phase: newPhase.rawValue,
                cycleIndex: cycleIndex,
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                elapsedTime: elapsedTime,
                currentPhaseTime: 0,
                previousPhase: previousPhase.rawValue,
                previousPhaseDuration: completedPhaseDuration
            )
        }

        let record = dataController.createSetRecord(
            sessionId: sessionId,
            phase: newPhase,
            cycleIndex: cycleIndex
        )
        record.category = selectedCategory
        record.name = selectedExercise
        record.load = currentLoad
        record.reps = currentReps
        record.note = currentNote
        record.session = currentSession
        currentSetRecord = record

        // Core Dataに即座に保存
        dataController.save()

        print("SessionManager: ✅ Phase changed to \(newPhase.rawValue), notifyWatch: \(notifyWatch)")
    }

    /// iPhone UIからのトグル操作
    private func togglePhaseInternal(notifyWatch: Bool) {
        print("SessionManager: 🔄 togglePhaseInternal() called, notifyWatch: \(notifyWatch)")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")

        guard currentPhase != .idle else {
            print("SessionManager: 🚀 togglePhase() starting new session from idle")
            startSession()
            return
        }

        let newPhase: WorkoutPhase = currentPhase == .work ? .rest : .work
        applyPhaseInternal(newPhase: newPhase, notifyWatch: notifyWatch)
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
        
        // 心拍数モニタリングを停止
        heartRateManager.stopMonitoring()

        // Watchが接続されている場合のみ、Watchワークアウト終了を通知
        if watchConnectivity.isWatchConnected {
            watchConnectivity.stopWatchWorkout()
        }

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

    @discardableResult
    private func ensureActiveSession(startTime: Date? = nil) -> Session? {
        if currentSession == nil {
            let resolvedStart = startTime ?? sessionStartTime ?? Date()
            sessionStartTime = sessionStartTime ?? resolvedStart

            let session = dataController.createSession()
            session.startedAt = resolvedStart
            currentSession = session
        }

        if let session = currentSession, session.id == nil {
            session.id = UUID()
        }

        if timer == nil, currentPhase != .idle {
            startTimer()
        }

        return currentSession
    }

    private func calculateTotalVolume() -> Double {
        guard let session = currentSession,
              let records = session.setRecords?.allObjects as? [SetRecord] else { return 0 }

        return records.reduce(0) { $0 + ($1.load * $1.reps) }
    }

    private func phase(from identifier: String) -> WorkoutPhase? {
        switch identifier.lowercased() {
        case "work", "筋トレ":
            return .work
        case "rest", "休憩":
            return .rest
        case "idle", "待機中":
            return .idle
        default:
            return WorkoutPhase(rawValue: identifier.capitalized)
        }
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
