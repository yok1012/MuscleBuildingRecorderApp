#if os(watchOS)
import Foundation
import HealthKit
import Combine
import WatchConnectivity

class WorkoutManager: NSObject, ObservableObject, WCSessionDelegate {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: Any? // HKLiveWorkoutBuilder handled dynamically
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var heartRateQuery: HKQuery?
    private var heartRateObserverQuery: HKObserverQuery?
    private var workoutStartDate: Date?
    private var heartRateAnchor: HKQueryAnchor?
    private var consecutiveEmptyResults = 0
    private var lastProcessedSampleDate: Date?
    @available(watchOS 9.0, *)
    private var liveDataSource: HKLiveWorkoutDataSource?
    private var phoneContext: [String: Any] = [:]
    private var lastPhoneSyncDate: Date?

    @Published var isWorkoutActive = false
    @Published var isPaused = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentPhaseTime: TimeInterval = 0  // 現在のフェーズの時間
    @Published var totalWorkTime: TimeInterval = 0     // 合計筋トレ時間
    @Published var totalRestTime: TimeInterval = 0     // 合計休憩時間
    @Published var debugMessage: String = "Init"
    @Published var sessionState: String = "NotStarted"
    @Published var queryStatus: String = "None"
    @Published var lastHeartRateTime: String = "Never"

    private var timer: Timer?
    private var realtimeHeartRateTimer: Timer?
    private var phaseStartTime: Date?  // 現在のフェーズの開始時刻
    private var currentPhase: String = "idle"  // "work", "rest", "idle"
    #if os(watchOS)
    private var wcSession: WCSession?
    #endif

    var elapsedTimeString: String {
        let time = Int(elapsedTime)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var currentPhaseTimeString: String {
        let time = Int(currentPhaseTime)
        let minutes = time / 60
        let seconds = time % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var totalWorkTimeString: String {
        let time = Int(totalWorkTime)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var totalRestTimeString: String {
        let time = Int(totalRestTime)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    override init() {
        super.init()
        setupWatchConnectivity()
    }

    private func setupWatchConnectivity() {
        #if os(watchOS)
        if WCSession.isSupported() {
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
            print("Watch: WCSession activated")
        }
        #endif
    }

    #if os(watchOS)
    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Watch: WCSession activation failed: \(error)")
        } else {
            print("Watch: WCSession activated with state: \(activationState.rawValue)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Watch: Received message from iPhone: \(message)")

        // コマンドタイプの処理
        if let command = message["command"] as? String {
            DispatchQueue.main.async {
                print("Watch: Processing command: \(command)")
                switch command {
                case "start":
                    print("Watch: Starting workout from iPhone command")
                    if !self.isWorkoutActive {
                        self.startWorkout()
                        self.debugMessage = "Started from iPhone"
                    } else {
                        print("Watch: Workout already active, ignoring start command")
                    }
                case "stop":
                    print("Watch: Stopping workout from iPhone command")
                    if self.isWorkoutActive {
                        self.endWorkout()
                        self.debugMessage = "Stopped from iPhone"
                    }
                case "pause":
                    print("Watch: Pausing workout from iPhone command")
                    if self.isWorkoutActive && !self.isPaused {
                        self.togglePause()
                        self.debugMessage = "Paused from iPhone"
                    }
                case "resume":
                    print("Watch: Resuming workout from iPhone command")
                    if self.isWorkoutActive && self.isPaused {
                        self.togglePause()
                        self.debugMessage = "Resumed from iPhone"
                    }
                default:
                    print("Watch: Unknown command: \(command)")
                }
            }
        }

        // フェーズ変更タイプの処理
        if let type = message["type"] as? String, type == "phaseChange" {
            if let phase = message["phase"] as? String {
                DispatchQueue.main.async {
                    print("Watch: Phase change received: \(phase)")
                    self.setPhase(phase)
                    self.debugMessage = "Phase: \(phase)"
                }
            }
        }
    }

    private func sendHeartRateToPhone(_ heartRate: Double) {
        notifyPhoneOfWorkout(heartRate: heartRate, elapsed: elapsedTime, force: true)
    }

    // iPhoneにワークアウトコマンドを送信
    private func sendWorkoutCommandToPhone(_ command: String) {
        guard let session = wcSession else { return }

        let message: [String: Any] = [
            "type": "command",
            "command": command,
            "timestamp": Date().timeIntervalSince1970
        ]

        print("Watch WorkoutManager: 📤 Sending command to iPhone: '\(command)'")

        if session.isReachable {
            // リアルタイム送信
            session.sendMessage(message, replyHandler: { response in
                print("Watch WorkoutManager: ✅ Command '\(command)' acknowledged by iPhone")
            }) { error in
                print("Watch WorkoutManager: ⚠️ Failed to send command '\(command)': \(error)")
                // フォールバック: applicationContextを使用
                self.updateApplicationContextWithCommand(command)
            }
        } else {
            // iPhoneが到達不可能な場合
            print("Watch WorkoutManager: 📦 iPhone not reachable, saving command to applicationContext")
            self.updateApplicationContextWithCommand(command)
        }
    }

    private func updateApplicationContextWithCommand(_ command: String) {
        guard let session = wcSession else { return }

        do {
            let context: [String: Any] = [
                "type": "command",
                "lastCommand": command,
                "commandTimestamp": Date().timeIntervalSince1970,
                "commandId": UUID().uuidString,
                "source": "WorkoutManager"
            ]
            try session.updateApplicationContext(context)
            print("Watch WorkoutManager: 💾 Command saved to applicationContext: '\(command)'")
        } catch {
            print("Watch WorkoutManager: ❌ Failed to update applicationContext: \(error)")
        }
    }
#endif

    func requestAuthorization() {
        debugMessage = "Requesting auth..."
        print("Watch: Requesting HealthKit authorization...")
        var shareTypes = Set<HKSampleType>()
        shareTypes.insert(HKObjectType.workoutType())
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            shareTypes.insert(heartRateType)
        }
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            shareTypes.insert(activeEnergyType)
        }

        var readTypes = Set<HKObjectType>()
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRateType)
        }
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            readTypes.insert(activeEnergyType)
        }
        readTypes.insert(HKObjectType.workoutType())

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            if let error = error {
                print("Watch: HealthKit authorization failed: \(error)")
                DispatchQueue.main.async {
                    self.debugMessage = "Auth failed"
                }
            } else if success {
                print("Watch: HealthKit authorization granted")
                DispatchQueue.main.async {
                    self.debugMessage = "Auth granted"
                }

                // Check actual authorization status
                let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
                let status = self.healthStore.authorizationStatus(for: heartRateType)
                print("Watch: Heart rate auth status: \(status.rawValue) (0=notDetermined, 1=sharingDenied, 2=sharingAuthorized)")
                DispatchQueue.main.async {
                    self.debugMessage = "Auth: \(status.rawValue)"
                }
            }
        }
    }

    func startWorkout() {
        debugMessage = "Starting..."
        sessionState = "Creating"
        queryStatus = "Initializing"
        lastHeartRateTime = "Waiting"
        consecutiveEmptyResults = 0
        heartRateAnchor = nil
        lastProcessedSampleDate = nil

        stopHeartRateMonitoring()

        guard HKHealthStore.isHealthDataAvailable() else {
            debugMessage = "No HealthKit!"
            sessionState = "Error"
            return
        }

        #if os(watchOS)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        let startDate = Date()
        workoutStartDate = startDate
        startTime = startDate
        pausedTime = 0

        do {
            workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutSession?.delegate = self
            debugMessage = "Session created"
            sessionState = "Created"

            workoutSession?.startActivity(with: startDate)
            sessionState = "Starting"

            if let session = workoutSession {
                healthStore.start(session)
            }

            if #available(watchOS 9.0, *) {
                print("Watch: Setting up HKLiveWorkoutBuilder (watchOS 9.0+)...")
                if let workoutBuilder = workoutSession?.associatedWorkoutBuilder() {
                    builder = workoutBuilder
                    workoutBuilder.delegate = self
                    let dataSource = HKLiveWorkoutDataSource(
                        healthStore: healthStore,
                        workoutConfiguration: configuration
                    )
                    liveDataSource = dataSource
                    workoutBuilder.dataSource = dataSource
                    print("Watch: HKLiveWorkoutDataSource configured")
                } else {
                    print("Watch WARNING: Could not get associatedWorkoutBuilder")
                }
            } else {
                print("Watch: watchOS < 9.0, skipping HKLiveWorkoutBuilder")
            }

            debugMessage = "Session started"

            if #available(watchOS 9.0, *) {
                if let workoutBuilder = builder as? HKLiveWorkoutBuilder {
                    print("Watch: Beginning data collection with HKLiveWorkoutBuilder...")
                    workoutBuilder.beginCollection(withStart: startDate) { success, error in
                        if let error = error {
                            print("Watch ERROR: Failed to begin collection: \(error.localizedDescription)")
                        }
                        DispatchQueue.main.async {
                            self.markWorkoutActive(startDate: startDate, message: success ? "Builder active" : "Builder failed")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.markWorkoutActive(startDate: startDate, message: "No builder")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.markWorkoutActive(startDate: startDate, message: "Legacy watchOS")
                }
            }
        } catch {
            print("Watch ERROR: Failed to start workout: \(error.localizedDescription)")
            debugMessage = "Start failed"
            sessionState = "Error"
        }
        #else
        debugMessage = "Not watchOS"
        sessionState = "N/A"
        #endif
    }

    func endWorkout() {
        stopHeartRateMonitoring()

        sessionState = "Ending"

        // iPhoneにワークアウト終了を通知（重要！）
        #if os(watchOS)
        sendWorkoutCommandToPhone("endSession")
        print("Watch WorkoutManager: 🛑 Sent endSession command to iPhone")
        #endif

        workoutSession?.end()

        #if os(watchOS)
        if #available(watchOS 9.0, *) {
            if let workoutBuilder = builder as? HKLiveWorkoutBuilder {
                workoutBuilder.endCollection(withEnd: Date()) { success, error in
                    workoutBuilder.finishWorkout { workout, error in
                        DispatchQueue.main.async {
                            self.isWorkoutActive = false
                            self.isPaused = false
                            self.stopTimer()
                            self.resetMetrics()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isWorkoutActive = false
                    self.isPaused = false
                    self.stopTimer()
                    self.resetMetrics()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isWorkoutActive = false
                self.isPaused = false
                self.stopTimer()
                self.resetMetrics()
            }
        }
        #else
        DispatchQueue.main.async {
            self.isWorkoutActive = false
            self.isPaused = false
            self.stopTimer()
            self.resetMetrics()
        }
        #endif
    }

    func togglePause() {
        if isPaused {
            workoutSession?.resume()
            isPaused = false
            startTimer()
            notifyPhoneOfWorkout(elapsed: elapsedTime, state: "running", force: true)
        } else {
            workoutSession?.pause()
            isPaused = true
            pausedTime = elapsedTime
            stopTimer()
            notifyPhoneOfWorkout(elapsed: elapsedTime, state: "paused", force: true)
        }
    }

    func setPhase(_ phase: String) {
        // 前のフェーズの時間を合計に加算
        if let startTime = phaseStartTime {
            let phaseTime = Date().timeIntervalSince(startTime)
            if currentPhase == "work" {
                totalWorkTime += phaseTime
            } else if currentPhase == "rest" {
                totalRestTime += phaseTime
            }
        }

        // 新しいフェーズを設定
        let previousPhase = currentPhase
        currentPhase = phase
        phaseStartTime = Date()
        currentPhaseTime = 0

        // ワークアウト開始時（idle→workの遷移時）にiPhoneに通知
        #if os(watchOS)
        if phase == "work" && previousPhase == "idle" {
            sendWorkoutCommandToPhone("startSession")
            print("Watch WorkoutManager: 🚀 Auto-sending startSession to iPhone (idle→work transition)")
        }
        #endif

        // iPhoneに通知
        notifyPhoneOfWorkout(state: phase, force: true)
    }

    private func markWorkoutActive(startDate: Date, message: String) {
        stopTimer()
        isWorkoutActive = true
        isPaused = false
        pausedTime = 0
        startTime = startDate
        startTimer()
        debugMessage = message
        notifyPhoneOfWorkout(elapsed: 0, state: "running", force: true)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.startTime else { return }
            let elapsed = self.pausedTime + Date().timeIntervalSince(startTime)
            self.elapsedTime = elapsed

            // 現在のフェーズ時間を更新
            if let phaseStart = self.phaseStartTime {
                self.currentPhaseTime = Date().timeIntervalSince(phaseStart)
            }

            self.notifyPhoneOfWorkout(elapsed: elapsed)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetMetrics() {
        heartRate = 0
        activeCalories = 0
        elapsedTime = 0
        currentPhaseTime = 0
        totalWorkTime = 0
        totalRestTime = 0
        currentPhase = "idle"
        phaseStartTime = nil
        startTime = nil
        pausedTime = 0
        debugMessage = "Reset"
        sessionState = "NotStarted"
        queryStatus = "None"
        lastHeartRateTime = "Never"
        workoutStartDate = nil
        heartRateAnchor = nil
        lastProcessedSampleDate = nil
        phoneContext.removeAll()
        lastPhoneSyncDate = nil
        notifyPhoneOfWorkout(elapsed: 0, state: "idle", force: true)
    }

    // MARK: - Heart Rate Monitoring
    private func stopHeartRateMonitoring() {
        notifyPhoneOfWorkout(elapsed: elapsedTime, state: "ended", force: true)

        realtimeHeartRateTimer?.invalidate()
        realtimeHeartRateTimer = nil

        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
            self.heartRateQuery = nil
        }

        if let heartRateObserverQuery {
            healthStore.stop(heartRateObserverQuery)
            self.heartRateObserverQuery = nil
        }

        heartRateAnchor = nil
        consecutiveEmptyResults = 0
        lastProcessedSampleDate = nil

        #if os(watchOS)
        if #available(watchOS 9.0, *) {
            liveDataSource = nil
        }
        #endif
    }

    private func activateHeartRateMonitoring() {
        guard heartRateQuery == nil else {
            return
        }

        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            queryStatus = "No HR type"
            debugMessage = "Failed: No HR type"
            return
        }

        let status = healthStore.authorizationStatus(for: heartRateType)
        if status == .sharingDenied {
            queryStatus = "Auth denied"
            debugMessage = "Heart rate denied"
            return
        }

        if status == .notDetermined {
            debugMessage = "Auth pending"
            requestAuthorization()
            return
        }

        debugMessage = "HR monitor starting"
        queryStatus = "Creating query..."

        startHeartRateStreaming(using: heartRateType)
        startHeartRateObserver(for: heartRateType)
        scheduleRealtimeFallback()
        notifyPhoneOfWorkout(elapsed: elapsedTime, state: "running", force: true)
    }

    private func startHeartRateStreaming(using heartRateType: HKQuantityType) {
        if let existingQuery = heartRateQuery {
            healthStore.stop(existingQuery)
        }

        let start = workoutStartDate ?? Date().addingTimeInterval(-300)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: nil,
            options: [.strictStartDate]
        )

        let anchoredQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: heartRateAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            self?.handleHeartRateSamples(samples, anchor: newAnchor, error: error, phase: "init")
        }

        anchoredQuery.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            self?.handleHeartRateSamples(samples, anchor: newAnchor, error: error, phase: "update")
        }

        healthStore.execute(anchoredQuery)
        heartRateQuery = anchoredQuery
        debugMessage = "HR streaming"
        queryStatus = "Anchored active"
    }

    private func startHeartRateObserver(for heartRateType: HKQuantityType) {
        if let observer = heartRateObserverQuery {
            healthStore.stop(observer)
        }

        let observerQuery = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                print("Watch ERROR: Observer query error: \(error.localizedDescription)")
            } else {
                self?.fetchMostRecentHeartRate(span: 180)
            }
            completionHandler()
        }

        heartRateObserverQuery = observerQuery
        healthStore.execute(observerQuery)
    }

    private func scheduleRealtimeFallback(interval: TimeInterval = 5.0) {
        realtimeHeartRateTimer?.invalidate()
        realtimeHeartRateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetchMostRecentHeartRate(span: 300)
        }
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?, anchor: HKQueryAnchor?, error: Error?, phase: String) {
        if let error = error {
            print("Watch ERROR: Heart rate query \(phase) error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.queryStatus = "Error"
                self.debugMessage = "Query err"
            }
            return
        }

        if let anchor = anchor {
            heartRateAnchor = anchor
        }

        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
            handleEmptyHeartRateSamples()
            return
        }

        consecutiveEmptyResults = 0
        processHeartRateSamples(quantitySamples)
    }

    private func handleEmptyHeartRateSamples(increment: Bool = true) {
        if increment {
            consecutiveEmptyResults += 1
        }

        if consecutiveEmptyResults >= 3 {
            DispatchQueue.main.async {
                self.queryStatus = "No data"
                self.lastHeartRateTime = "No samples"
                self.debugMessage = "Empty result"
            }
        } else {
            DispatchQueue.main.async {
                self.debugMessage = "Waiting HR (\(self.consecutiveEmptyResults))"
            }
        }

        if consecutiveEmptyResults == 3 {
            fetchMostRecentHeartRate(span: 600)
        } else if consecutiveEmptyResults > 6 {
            restartHeartRateStreaming()
        }
    }

    private func restartHeartRateStreaming() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }
        heartRateAnchor = nil
        startHeartRateStreaming(using: heartRateType)
    }

    private func fetchMostRecentHeartRate(span: TimeInterval) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let now = Date()
        let start = now.addingTimeInterval(-span)

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: [.strictStartDate, .strictEndDate]
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self else { return }
            if let error = error {
                print("Watch ERROR: Sample query error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.queryStatus = "Error"
                    self.debugMessage = "Query err"
                }
                return
            }

            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                self.handleEmptyHeartRateSamples()
                return
            }

            self.consecutiveEmptyResults = 0
            self.processHeartRateSamples(quantitySamples)
        }

        healthStore.execute(query)
    }

    private func processHeartRateSamples(_ heartRateSamples: [HKQuantitySample]) {
        guard let latestSample = heartRateSamples.sorted(by: { $0.startDate > $1.startDate }).first else {
            return
        }

        if let lastDate = lastProcessedSampleDate, abs(latestSample.startDate.timeIntervalSince(lastDate)) < 0.5 {
            return
        }

        lastProcessedSampleDate = latestSample.startDate

        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let value = latestSample.quantity.doubleValue(for: unit)
        let age = Date().timeIntervalSince(latestSample.startDate)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.heartRate = value
            self.lastHeartRateTime = age < 1.5 ? "Live" : "\(Int(age))s ago"
            self.queryStatus = "Live: \(Int(value))"
            self.debugMessage = age <= 10 ? "Fresh" : "Old: \(Int(age))s"
            self.sendHeartRateToPhone(value)
        }
    }

    // MARK: - Debug Utilities
    private func notifyPhoneOfWorkout(heartRate: Double? = nil,
                                      elapsed: TimeInterval? = nil,
                                      state: String? = nil,
                                      force: Bool = false) {
        #if os(watchOS)
        guard let session = wcSession else { return }

        if let heartRate {
            phoneContext["heartRate"] = heartRate
        }
        if let elapsed {
            phoneContext["elapsedTime"] = elapsed
        }
        if let state {
            phoneContext["workoutState"] = state
        }
        phoneContext["timestamp"] = Date().timeIntervalSince1970

        let now = Date()
        let elapsedSinceLast = now.timeIntervalSince(lastPhoneSyncDate ?? .distantPast)
        let shouldSend = force || elapsedSinceLast >= 1.0 || session.isReachable

        guard shouldSend else { return }

        lastPhoneSyncDate = now

        if session.isReachable {
            session.sendMessage(phoneContext, replyHandler: nil) { error in
                print("Watch: Failed to send update to phone: \(error)")
            }
        } else {
            do {
                try session.updateApplicationContext(phoneContext)
            } catch {
                print("Watch: Failed to update application context: \(error)")
            }
        }
        #endif
    }

    func debugTriggerHeartRate() {
        #if os(watchOS)
        debugMessage = "Manual trigger"
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            debugMessage = "No HR type"
            return
        }

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: []
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 10,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error = error {
                    self.debugMessage = "Err: \(error.localizedDescription)"
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    self.debugMessage = "No samples in 24h"
                    return
                }

                self.processHeartRateSamples(quantitySamples)

                if quantitySamples.count > 1 {
                    self.debugMessage = "\(quantitySamples.count) samples, newest: \(Int(self.heartRate))"
                } else if let sampleDate = quantitySamples.first?.startDate {
                    let age = Int(Date().timeIntervalSince(sampleDate))
                    self.debugMessage = "Got: \(Int(self.heartRate)) (\(age)s ago)"
                }
            }
        }
        healthStore.execute(query)
        #else
        debugMessage = "Not watchOS"
        #endif
    }


}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didChangeTo toState: HKWorkoutSessionState,
                       from fromState: HKWorkoutSessionState,
                       date: Date) {
        print("Watch: Workout session state changed from \(fromState.rawValue) to \(toState.rawValue)")
        print("Watch: State names: \(stateString(fromState)) -> \(stateString(toState))")

        // UIに状態を表示
        DispatchQueue.main.async {
            self.sessionState = self.stateString(toState)
        }

        // Handle specific state transitions
        switch toState {
        case .running:
            print("Watch: Session is now RUNNING - heart rate should be available")
            // ワークアウトが実行中 - リアルタイム心拍数を開始
            let stateChangeDate = date
            DispatchQueue.main.async {
                if self.workoutStartDate == nil {
                    self.workoutStartDate = stateChangeDate
                }
            self.debugMessage = "Session RUNNING"
            self.activateHeartRateMonitoring()
            }
        case .paused:
            print("Watch: Session is PAUSED")
            DispatchQueue.main.async {
                self.debugMessage = "Session PAUSED"
            }
        case .stopped, .ended:
            print("Watch: Session is STOPPED/ENDED")
            DispatchQueue.main.async {
                self.debugMessage = "Session ENDED"
                self.stopHeartRateMonitoring()
                self.workoutStartDate = nil
            }
        case .notStarted:
            print("Watch: Session is NOT STARTED")
            DispatchQueue.main.async {
                self.debugMessage = "Session NOT STARTED"
            }
        case .prepared:
            print("Watch: Session is PREPARED")
            DispatchQueue.main.async {
                self.debugMessage = "Session PREPARED"
            }
        @unknown default:
            print("Watch: Unknown session state")
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didFailWithError error: Error) {
        print("Watch ERROR: Workout session failed: \(error.localizedDescription)")
        print("Watch ERROR details: \(error)")
    }

    private func stateString(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted: return "NotStarted"
        case .running: return "Running"
        case .ended: return "Ended"
        case .paused: return "Paused"
        case .prepared: return "Prepared"
        case .stopped: return "Stopped"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
#if os(watchOS)
@available(watchOS 9.0, *)
extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                       didCollectDataOf collectedTypes: Set<HKSampleType>) {
        print("Watch: HKLiveWorkoutBuilder collected data for \(collectedTypes.count) types")

        for type in collectedTypes {
            if let quantityType = type as? HKQuantityType {
                print("Watch: Processing quantity type: \(quantityType)")
            }

            guard let quantityType = type as? HKQuantityType else {
                print("Watch: Skipping non-quantity type: \(type)")
                continue
            }

            switch quantityType {
            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                print("Watch: Heart rate data collected by builder")
                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    if let mostRecent = statistics.mostRecentQuantity() {
                        let value = mostRecent.doubleValue(for: .count().unitDivided(by: .minute()))
                        print("Watch: Builder heart rate: \(value) bpm")
                        DispatchQueue.main.async {
                            self.heartRate = value
                            print("Watch: Updated UI with builder heart rate: \(value)")
                        }
                    } else {
                        print("Watch: No mostRecentQuantity for heart rate")
                    }
                } else {
                    print("Watch: No statistics for heart rate")
                }

            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                print("Watch: Active energy data collected")
                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    if let sum = statistics.sumQuantity() {
                        let calories = sum.doubleValue(for: .kilocalorie())
                        print("Watch: Active calories: \(calories)")
                        DispatchQueue.main.async {
                            self.activeCalories = calories
                        }
                    }
                }

            default:
                print("Watch: Other quantity type collected: \(quantityType)")
                break
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        print("Watch: HKLiveWorkoutBuilder collected event")
    }
}
#endif
#endif
