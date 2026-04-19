#if os(watchOS)
import Foundation
import HealthKit
import Combine
import WatchConnectivity

enum CommandStatus {
    case idle, sending, success, failed, savedToContext
}

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

    // ContentView向けの情報（WatchConnectivityDelegate廃止に伴い統合）
    @Published var receivedExercise: (category: String, name: String)?
    @Published var receivedCycleIndex: Int?
    @Published var lastCommandAck: (command: String, success: Bool)?
    @Published var lastCommandStatus: CommandStatus = .idle

    private var timer: Timer?
    private var realtimeHeartRateTimer: Timer?
    private var phaseStartTime: Date?  // 現在のフェーズの開始時刻
    private var lastLocalPhaseChangeDate: Date? // ローカルでのフェーズ変更時刻（競合解決用）
    private var workPhaseAccumulated: TimeInterval = 0  // 確定済み筋トレ時間
    private var restPhaseAccumulated: TimeInterval = 0  // 確定済み休憩時間
    @Published var currentPhase: String = "idle"  // "work", "rest", "idle" - ContentViewで監視可能
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
        
        // セッション復元を試行
        restoreSessionIfNeeded()
    }

    // MARK: - Standalone Mode Properties
    
    /// Watch単独モード（iPhone未接続で動作中）
    @Published var isStandaloneMode: Bool = false
    
    /// 同期待ちデータがあるか
    @Published var hasPendingSyncData: Bool = false
    
    /// ローカルストレージへの参照
    private let localStorage = WatchLocalStorage.shared
    
    // MARK: - Session Restoration
    
    /// アプリ起動時にセッションを復元
    private func restoreSessionIfNeeded() {
        guard let savedSession = localStorage.restoreSession() else {
            print("Watch WorkoutManager: No session to restore")
            return
        }
        
        print("Watch WorkoutManager: Restoring session from local storage")
        
        // 保存されたセッションデータを復元
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.currentPhase = savedSession.currentPhase
            self.totalWorkTime = savedSession.totalWorkTime
            self.totalRestTime = savedSession.totalRestTime
            self.elapsedTime = savedSession.elapsedTime
            self.isStandaloneMode = true
            
            // ワークアウトを再開するかユーザーに確認するためのフラグ
            // （実際のHKWorkoutSessionは再開始する必要がある）
            self.debugMessage = "Session restored"
            
            print("Watch WorkoutManager: Session restored - Phase: \(savedSession.currentPhase), Work: \(savedSession.totalWorkTime)s, Rest: \(savedSession.totalRestTime)s")
        }
    }
    
    // MARK: - Standalone Mode Methods
    
    /// Watch単独でワークアウトを開始
    func startStandaloneWorkout() {
        print("Watch WorkoutManager: Starting standalone workout")
        isStandaloneMode = true
        
        // ローカルストレージにセッションを作成
        let session = localStorage.startSession()
        print("Watch WorkoutManager: Local session created: \(session.id)")
        
        // 通常のワークアウト開始
        startWorkout()
        
        // iPhoneへの通知を試みる（失敗しても継続）
        if let wcSession = wcSession, wcSession.isReachable {
            sendWorkoutCommandToPhone("startSession")
            isStandaloneMode = false  // iPhone接続されていればスタンドアロンモードではない
        } else {
            print("Watch WorkoutManager: iPhone not reachable, continuing in standalone mode")
        }
    }
    
    /// iPhoneが接続されたときに、蓄積データを同期
    func syncPendingDataToPhone() {
        let pendingSessions = localStorage.loadPendingSyncData()
        guard !pendingSessions.isEmpty else {
            print("Watch WorkoutManager: No pending data to sync")
            return
        }
        
        guard let session = wcSession, session.isReachable else {
            print("Watch WorkoutManager: Cannot sync - iPhone not reachable")
            return
        }
        
        print("Watch WorkoutManager: Syncing \(pendingSessions.count) pending sessions to iPhone")
        
        for pendingSession in pendingSessions {
            let syncData: [String: Any] = [
                "type": "syncSession",
                "sessionId": pendingSession.id.uuidString,
                "startTime": pendingSession.startTime.timeIntervalSince1970,
                "endTime": pendingSession.endTime?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                "totalWorkTime": pendingSession.totalWorkTime,
                "totalRestTime": pendingSession.totalRestTime,
                "elapsedTime": pendingSession.elapsedTime,
                "heartRateSamplesCount": pendingSession.heartRateSamples.count,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            session.sendMessage(syncData, replyHandler: { [weak self] response in
                if response["success"] as? Bool == true {
                    // 同期成功 - ローカルデータを削除
                    self?.localStorage.removePendingSyncData(sessionId: pendingSession.id)
                    print("Watch WorkoutManager: Session \(pendingSession.id) synced successfully")
                }
            }, errorHandler: { error in
                print("Watch WorkoutManager: Failed to sync session: \(error.localizedDescription)")
            })
        }
        
        updatePendingSyncStatus()
    }
    
    /// 同期待ちステータスを更新
    private func updatePendingSyncStatus() {
        DispatchQueue.main.async { [weak self] in
            self?.hasPendingSyncData = self?.localStorage.hasPendingData() ?? false
        }
    }
    
    /// 現在のセッション状態をローカルストレージに保存
    private func saveCurrentStateToLocalStorage() {
        guard isStandaloneMode, isWorkoutActive else { return }
        
        localStorage.updatePhase(currentPhase, cycleIndex: 0)  // cycleIndexはWatch側では単純化
        localStorage.updateTimes(
            totalWorkTime: totalWorkTime,
            totalRestTime: totalRestTime,
            elapsedTime: elapsedTime
        )
    }
    
    /// 心拍数をローカルストレージに保存（スタンドアロンモード時）
    private func saveHeartRateToLocalStorage(_ bpm: Double) {
        guard isStandaloneMode, isWorkoutActive, bpm > 0 else { return }
        localStorage.addHeartRateSample(bpm: bpm, phase: currentPhase)
    }

    private func setupWatchConnectivity() {
        #if os(watchOS)
        if WCSession.isSupported() {
            print("Watch WorkoutManager: 🔧 Setting up WCSession...")
            wcSession = WCSession.default
            wcSession?.delegate = self
            wcSession?.activate()
            print("Watch WorkoutManager: ✅ WCSession activated with delegate: \(String(describing: wcSession?.delegate))")

            // 初期状態を確認
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let session = self?.wcSession {
                    print("Watch WorkoutManager: 📊 WCSession status check:")
                    print("  - isReachable: \(session.isReachable)")
                    print("  - isCompanionAppInstalled: \(session.isCompanionAppInstalled)")
                    print("  - activationState: \(session.activationState.rawValue)")
                }
            }
        } else {
            print("Watch WorkoutManager: ❌ WCSession is not supported")
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

            // iPhone から受信済みの applicationContext を確認
            // （Watch後追い起動時にiPhoneのセッション状態を反映するため）
            let receivedContext = session.receivedApplicationContext
            if !receivedContext.isEmpty {
                print("Watch WorkoutManager: 📦 Processing existing receivedApplicationContext on activation")
                handleIncomingMessage(receivedContext)
            }

            // iPhoneがreachableなら状態をリクエスト（applicationContextが古い可能性対策）
            if session.isReachable {
                requestStateFromPhone()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("Watch WorkoutManager: Reachability changed to: \(session.isReachable)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if session.isReachable {
                // iPhoneに接続された
                print("Watch WorkoutManager: iPhone connected")

                // スタンドアロンモードで動作中なら、iPhoneに状態を同期
                if self.isStandaloneMode && self.isWorkoutActive {
                    print("Watch WorkoutManager: Syncing current standalone session to iPhone")
                    self.sendWorkoutCommandToPhoneWithContext(
                        "syncState",
                        previousPhase: nil,
                        previousPhaseDuration: nil
                    )
                    self.isStandaloneMode = false  // iPhoneと連携モードに切り替え
                } else if !self.isWorkoutActive {
                    // Watchがidle状態でiPhoneに接続された場合、
                    // iPhoneでセッション中かもしれないので状態をリクエスト
                    self.requestStateFromPhone()
                }

                // 保留中のデータを同期
                self.syncPendingDataToPhone()
            } else {
                // iPhoneから切断された
                print("Watch WorkoutManager: iPhone disconnected")
                
                // ワークアウト中ならスタンドアロンモードに切り替え
                if self.isWorkoutActive && !self.isStandaloneMode {
                    print("Watch WorkoutManager: Switching to standalone mode")
                    self.isStandaloneMode = true
                    
                    // ローカルストレージにセッションを開始
                    _ = self.localStorage.startSession()
                    self.saveCurrentStateToLocalStorage()
                }
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("Watch WorkoutManager: 📥 Received message from iPhone with reply handler")

        // pingメッセージへの応答
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["type": "pong", "timestamp": Date().timeIntervalSince1970])
            return
        }

        // メッセージを処理
        handleIncomingMessage(message)
        replyHandler(["received": true, "timestamp": Date().timeIntervalSince1970])
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Watch WorkoutManager: 📥 Received message from iPhone (no reply handler)")

        // メッセージを処理
        handleIncomingMessage(message)
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // メッセージタイプによるディスパッチ
            if let type = message["type"] as? String {
                switch type {
                case "wakeUp":
                    if !self.isWorkoutActive {
                        self.startWorkout()
                        self.setPhase("work")
                    }

                case "exerciseChange":
                    if let category = message["category"] as? String,
                       let exercise = message["exercise"] as? String {
                        self.receivedExercise = (category: category, name: exercise)
                    }

                case "phaseChange":
                    self.handlePhaseChangeMessage(message)

                case "command":
                    if let command = message["command"] as? String {
                        self.handleCommandMessage(command, message: message)
                    }

                case "commandAck":
                    if let command = message["command"] as? String,
                       let success = message["success"] as? Bool {
                        self.lastCommandAck = (command: command, success: success)
                    }

                default:
                    break
                }
            }

            // コマンドキーによる処理（type がない場合やlastCommandフォールバック用）
            if message["type"] == nil, let command = message["command"] as? String {
                self.handleCommandMessage(command, message: message)
            } else if message["type"] == nil, let command = message["lastCommand"] as? String {
                self.handleCommandMessage(command, message: message)
            }

            // 種目情報のチェック（applicationContext経由）
            if let category = message["currentCategory"] as? String,
               let exercise = message["currentExercise"] as? String {
                self.receivedExercise = (category: category, name: exercise)
            }

            // サイクルインデックスの更新
            if let cycleIndex = message["cycleIndex"] as? Int {
                self.receivedCycleIndex = cycleIndex
            }

            // wakeUpフラグのチェック（applicationContext経由）
            if message["wakeUp"] as? Bool == true {
                if !self.isWorkoutActive {
                    self.startWorkout()
                    self.setPhase("work")
                }
            }
        }
    }

    private func handlePhaseChangeMessage(_ message: [String: Any]) {
        let phaseString = (message["phase"] as? String) ?? (message["currentPhase"] as? String)
        guard let phaseString else { return }

        // 古いメッセージによる上書き防止
        if let messageTimestamp = message["timestamp"] as? TimeInterval {
            let messageDate = Date(timeIntervalSince1970: messageTimestamp)
            if let lastLocalChange = lastLocalPhaseChangeDate {
                if messageDate < lastLocalChange.addingTimeInterval(-1.0) {
                    print("Watch WorkoutManager: ⚠️ Ignoring stale phase change from iPhone")
                    return
                }
            }
        }

        let totalWork = message["totalWorkTime"] as? TimeInterval
        let totalRest = message["totalRestTime"] as? TimeInterval
        let elapsed = message["elapsedTime"] as? TimeInterval
        let phaseTime = message["currentPhaseTime"] as? TimeInterval
        let previousPhase = message["previousPhase"] as? String
        let previousDuration = message["previousPhaseDuration"] as? TimeInterval

        applyPhaseChangeFromPhone(
            phase: phaseString,
            totalWorkTime: totalWork,
            totalRestTime: totalRest,
            elapsedTime: elapsed,
            currentPhaseTime: phaseTime,
            previousPhase: previousPhase,
            previousPhaseDuration: previousDuration
        )
        debugMessage = "Phase: \(phaseString)"

        if let index = message["cycleIndex"] as? Int {
            receivedCycleIndex = index
        }
    }

    private func handleCommandMessage(_ command: String, message: [String: Any]) {
        print("Watch WorkoutManager: Processing command: \(command)")
        switch command {
        case "start", "startSession":
            if !isWorkoutActive {
                startWorkout()
                setPhase("work")
                debugMessage = "Started from iPhone"
            }
        case "stop", "endSession":
            if isWorkoutActive {
                endWorkout()
                debugMessage = "Stopped from iPhone"
            }
        case "pause":
            if isWorkoutActive && !isPaused {
                togglePause()
                debugMessage = "Paused from iPhone"
            }
        case "resume":
            if isWorkoutActive && isPaused {
                togglePause()
                debugMessage = "Resumed from iPhone"
            }
        case "togglePhase":
            if isWorkoutActive {
                let newPhase = currentPhase == "work" ? "rest" : "work"
                // iPhoneからのフェーズ変更として処理
                let totalWork = message["totalWorkTime"] as? TimeInterval
                let totalRest = message["totalRestTime"] as? TimeInterval
                let elapsed = message["elapsedTime"] as? TimeInterval
                let phaseTime = message["currentPhaseTime"] as? TimeInterval
                applyPhaseChangeFromPhone(
                    phase: newPhase,
                    totalWorkTime: totalWork,
                    totalRestTime: totalRest,
                    elapsedTime: elapsed,
                    currentPhaseTime: phaseTime ?? 0,
                    previousPhase: currentPhase,
                    previousPhaseDuration: nil
                )
            } else {
                startWorkout()
                setPhase("work")
            }
        default:
            print("Watch WorkoutManager: Unknown command: \(command)")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Watch WorkoutManager: 📦 Received applicationContext from iPhone")
        print("Watch WorkoutManager: Context keys: \(applicationContext.keys.sorted())")

        // applicationContextを処理
        handleIncomingMessage(applicationContext)
    }

    // 心拍数送信のスロットリング用
    private var lastHeartRateSendTime: Date?
    private let heartRateSendInterval: TimeInterval = 0.5  // 0.5秒間隔に制限

    private func sendHeartRateToPhone(_ heartRate: Double) {
        guard let session = wcSession, heartRate > 0 else { return }

        // スロットリング: 0.5秒以内の重複送信を防ぐ
        let now = Date()
        if let lastSend = lastHeartRateSendTime,
           now.timeIntervalSince(lastSend) < heartRateSendInterval {
            return
        }
        lastHeartRateSendTime = now

        let message: [String: Any] = [
            "type": "heartRate",
            "heartRate": heartRate,
            "timestamp": now.timeIntervalSince1970
        ]

        // reachableな場合のみ送信（applicationContextは使わない - 頻度が高すぎる）
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    /// iPhoneに現在の状態をリクエスト（後追い起動時に使用）
    private func requestStateFromPhone() {
        guard let session = wcSession, session.isReachable else { return }

        let message: [String: Any] = [
            "type": "requestState",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { [weak self] response in
            print("Watch WorkoutManager: ✅ State request sent to iPhone")
            // iPhoneが応答としてphaseChangeメッセージを送信する
        }, errorHandler: { error in
            print("Watch WorkoutManager: ⚠️ State request failed: \(error.localizedDescription)")
        })

        print("Watch WorkoutManager: 📤 Requesting current state from iPhone")
    }

    // iPhoneにワークアウトコマンドを送信（時間データを含む）
    func sendWorkoutCommandToPhone(_ command: String) {
        sendWorkoutCommandToPhoneWithContext(command, previousPhase: nil, previousPhaseDuration: nil)
    }

    func sendWorkoutCommandToPhoneWithContext(
        _ command: String,
        previousPhase: String?,
        previousPhaseDuration: TimeInterval?
    ) {
        guard let session = wcSession else {
            print("Watch WorkoutManager: ⚠️ WCSession not available, setting up...")
            setupWatchConnectivity()
            return
        }

        print("Watch WorkoutManager: 📤 Sending command '\(command)' (isReachable: \(session.isReachable))")

        // コマンドごとにユニークIDを生成（重複排除用）
        let commandId = UUID().uuidString

        // メッセージを構築
        var message: [String: Any] = [
            "type": "command",
            "command": command,
            "commandId": commandId,
            "timestamp": Date().timeIntervalSince1970,
            "source": "WorkoutManager",
            "totalWorkTime": totalWorkTime,
            "totalRestTime": totalRestTime,
            "currentPhaseTime": currentPhaseTime,
            "elapsedTime": elapsedTime,
            "currentPhase": currentPhase
        ]

        if let startTime = phaseStartTime {
            message["phaseStartDate"] = startTime.timeIntervalSince1970
        }

        // previousPhase情報を追加
        if let previousPhase = previousPhase {
            message["previousPhase"] = previousPhase
        }
        if let previousPhaseDuration = previousPhaseDuration {
            message["previousPhaseDuration"] = previousPhaseDuration
        }

        // applicationContextを更新（バックアップとして常に更新）
        updateApplicationContextWithMessage(message)

        // 重要なコマンドの場合は常にsendMessageを試みる
        // isReachableがfalseでも、バックグラウンド起動の可能性があるため試行する（False Negative対策）
        if (command == "startSession" || command == "endSession" || command == "togglePhase" || command == "showExerciseSelection") {
            session.sendMessage(message, replyHandler: { [weak self] response in
                print("Watch WorkoutManager: ✅ Command '\(command)' acknowledged by iPhone")
                DispatchQueue.main.async {
                    self?.lastCommandStatus = .success
                }
            }, errorHandler: { [weak self] error in
                print("Watch WorkoutManager: ❌ Failed to send command '\(command)': \(error.localizedDescription)")
                // エラー時はapplicationContextがバックアップとして機能する
                DispatchQueue.main.async {
                    self?.lastCommandStatus = .savedToContext
                }
            })
        }
    }

    private func updateApplicationContextWithMessage(_ message: [String: Any]) {
        guard let session = wcSession else { return }

        do {
            var context = message
            // commandId は呼び出し元で生成済み。なければフォールバック追加
            if context["commandId"] == nil {
                context["commandId"] = UUID().uuidString
            }
            if let command = message["command"] as? String {
                context["lastCommand"] = command  // iPhone側のフォールバック処理用
            }
            try session.updateApplicationContext(context)
            print("Watch WorkoutManager: 💾 ApplicationContext updated")
        } catch {
            print("Watch WorkoutManager: ❌ Context update failed: \(error.localizedDescription)")
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
        
        // スタンドアロンモードの場合、ローカルストレージにセッションを完了として保存
        if isStandaloneMode {
            if let completedSession = localStorage.completeSession() {
                print("Watch WorkoutManager: Session completed and saved locally: \(completedSession.id)")
            }
        }

        // iPhoneにワークアウト終了を通知（重要！）
        #if os(watchOS)
        sendWorkoutCommandToPhone("endSession")
        print("Watch WorkoutManager: 🛑 Sent endSession command to iPhone")
        
        // iPhoneが接続されている場合、同期を試みる
        if let session = wcSession, session.isReachable {
            syncPendingDataToPhone()
        }
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
                            self.isStandaloneMode = false
                            self.stopTimer()
                            self.resetMetrics()
                            self.updatePendingSyncStatus()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isWorkoutActive = false
                    self.isPaused = false
                    self.isStandaloneMode = false
                    self.stopTimer()
                    self.resetMetrics()
                    self.updatePendingSyncStatus()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isWorkoutActive = false
                self.isPaused = false
                self.isStandaloneMode = false
                self.stopTimer()
                self.resetMetrics()
                self.updatePendingSyncStatus()
            }
        }
        #else
        DispatchQueue.main.async {
            self.isWorkoutActive = false
            self.isPaused = false
            self.isStandaloneMode = false
            self.stopTimer()
            self.resetMetrics()
            self.updatePendingSyncStatus()
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

    func setPhase(_ phase: String, fromRemote: Bool = false) {
        // 前のフェーズの確定時間を累積変数に加算
        if let startTime = phaseStartTime {
            let phaseTime = Date().timeIntervalSince(startTime)
            if currentPhase == "work" {
                workPhaseAccumulated += phaseTime
            } else if currentPhase == "rest" {
                restPhaseAccumulated += phaseTime
            }
        }

        // 新しいフェーズを設定
        currentPhase = phase
        phaseStartTime = Date()
        currentPhaseTime = 0
        // totalWorkTime/totalRestTime はタイマーで毎秒更新されるので、ここでは触らない

        // ローカル操作の場合はタイムスタンプを更新（古いリモート更新を無視するため）
        if !fromRemote {
            lastLocalPhaseChangeDate = Date()
        }

        // 注意: iPhoneへの通知はContentViewが責任を持つ（重複送信を避けるため）
        // notifyPhoneOfWorkout/sendWorkoutCommandToPhoneはここでは呼ばない
    }

    func applyPhaseChangeFromPhone(
        phase: String,
        totalWorkTime: TimeInterval?,
        totalRestTime: TimeInterval?,
        elapsedTime: TimeInterval?,
        currentPhaseTime: TimeInterval?,
        previousPhase _: String?,
        previousPhaseDuration _: TimeInterval?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // 累積値をiPhoneから受信した値で設定
            if let totalWorkTime {
                self.totalWorkTime = totalWorkTime
            }
            if let totalRestTime {
                self.totalRestTime = totalRestTime
            }

            let aggregateElapsed: TimeInterval?
            if let elapsedTime {
                aggregateElapsed = elapsedTime
            } else if let totalWorkTime, let totalRestTime {
                aggregateElapsed = totalWorkTime + totalRestTime
            } else {
                aggregateElapsed = nil
            }

            if let aggregateElapsed {
                self.elapsedTime = aggregateElapsed
                self.startTime = Date().addingTimeInterval(-aggregateElapsed)
            }

            if let currentPhaseTime {
                self.currentPhaseTime = max(currentPhaseTime, 0)
                self.phaseStartTime = Date().addingTimeInterval(-self.currentPhaseTime)
            } else if self.phaseStartTime == nil {
                self.phaseStartTime = Date()
                self.currentPhaseTime = 0
            }

            let normalizedPhase = phase.lowercased()
            self.currentPhase = normalizedPhase

            // workPhaseAccumulated/restPhaseAccumulated を設定
            // 新フェーズの現在フェーズ時間を差し引いた値が確定済み累積時間
            let resolvedPhaseTime = self.currentPhaseTime
            if normalizedPhase == "work" {
                self.workPhaseAccumulated = (self.totalWorkTime - resolvedPhaseTime)
                self.restPhaseAccumulated = self.totalRestTime
            } else if normalizedPhase == "rest" {
                self.workPhaseAccumulated = self.totalWorkTime
                self.restPhaseAccumulated = (self.totalRestTime - resolvedPhaseTime)
            } else {
                self.workPhaseAccumulated = self.totalWorkTime
                self.restPhaseAccumulated = self.totalRestTime
            }

            let isActive = normalizedPhase != "idle"
            self.isWorkoutActive = isActive
            self.isPaused = false

            if isActive {
                if self.timer == nil {
                    self.pausedTime = 0
                    if self.startTime == nil {
                        self.startTime = Date()
                    }
                    self.startTimer()
                }
            } else {
                self.stopTimer()
                self.pausedTime = 0
                self.currentPhaseTime = 0
            }

            self.lastPhoneSyncDate = Date()
            self.debugMessage = "Phone sync \(normalizedPhase)"
        }
    }

    private func markWorkoutActive(startDate: Date, message: String) {
        stopTimer()
        isWorkoutActive = true
        isPaused = false
        pausedTime = 0
        startTime = startDate
        startTimer()
        debugMessage = message

        // iPhoneにワークアウト開始を通知（重要！）
        // previousPhase情報も含めて送信
        #if os(watchOS)
        sendWorkoutCommandToPhoneWithContext(
            "startSession",
            previousPhase: nil,
            previousPhaseDuration: nil
        )
        print("Watch WorkoutManager: 🚀 Sent startSession command to iPhone from markWorkoutActive")
        #endif

        notifyPhoneOfWorkout(elapsed: 0, state: "running", force: true)
    }

    private func startTimer() {
        var updateCounter = 0
        var localSaveCounter = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let startTime = self.startTime else { return }
            let elapsed = self.pausedTime + Date().timeIntervalSince(startTime)
            self.elapsedTime = elapsed

            // 現在のフェーズ時間を更新
            if let phaseStart = self.phaseStartTime {
                self.currentPhaseTime = Date().timeIntervalSince(phaseStart)
            }

            // totalWorkTime/totalRestTime をリアルタイム計算
            if self.currentPhase == "work" {
                self.totalWorkTime = self.workPhaseAccumulated + self.currentPhaseTime
                self.totalRestTime = self.restPhaseAccumulated
            } else if self.currentPhase == "rest" {
                self.totalWorkTime = self.workPhaseAccumulated
                self.totalRestTime = self.restPhaseAccumulated + self.currentPhaseTime
            }

            // 2秒に1回iPhoneに通知（時間同期のため）
            updateCounter += 1
            if updateCounter >= 2 {
                updateCounter = 0
                self.notifyPhoneOfWorkout(heartRate: self.heartRate, elapsed: elapsed)
            }

            // スタンドアロンモード時は5秒に1回ローカルストレージに保存
            if self.isStandaloneMode {
                localSaveCounter += 1
                if localSaveCounter >= 5 {
                    localSaveCounter = 0
                    self.saveCurrentStateToLocalStorage()
                }
            }
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
        workPhaseAccumulated = 0
        restPhaseAccumulated = 0
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
            
            // スタンドアロンモード時はローカルストレージにも保存
            self.saveHeartRateToLocalStorage(value)
        }
    }

    // MARK: - Debug Utilities
    private func notifyPhoneOfWorkout(heartRate: Double? = nil,
                                      elapsed: TimeInterval? = nil,
                                      state: String? = nil,
                                      force: Bool = false) {
        #if os(watchOS)
        guard let session = wcSession else { return }

        // 心拍データをcontextに含める（updateApplicationContext経由でもiPhoneに届くようにする）
        if let hr = heartRate, hr > 0 {
            phoneContext["heartRate"] = hr
        } else if self.heartRate > 0 {
            phoneContext["heartRate"] = self.heartRate
        }

        if let elapsed {
            phoneContext["elapsedTime"] = elapsed
        }
        if let state {
            phoneContext["workoutState"] = state
        }
        phoneContext["timestamp"] = Date().timeIntervalSince1970

        // 時間データを常に含める（心拍数は除外）
        phoneContext["totalWorkTime"] = totalWorkTime
        phoneContext["totalRestTime"] = totalRestTime
        phoneContext["currentPhaseTime"] = currentPhaseTime
        phoneContext["currentPhase"] = currentPhase

        // コマンド関連キーを除外（タイマー更新でコマンドを上書きしない）
        phoneContext.removeValue(forKey: "command")
        phoneContext.removeValue(forKey: "lastCommand")
        phoneContext.removeValue(forKey: "commandId")
        phoneContext.removeValue(forKey: "type")

        let now = Date()
        let elapsedSinceLast = now.timeIntervalSince(lastPhoneSyncDate ?? .distantPast)

        // 通信頻度を制限（強制の場合を除き、最低2秒間隔）
        let minInterval: TimeInterval = force ? 0 : 2.0
        guard elapsedSinceLast >= minInterval else { return }

        lastPhoneSyncDate = now

        // applicationContextのみ更新（過剰なsendMessageを防ぐ）
        do {
            try session.updateApplicationContext(phoneContext)

            // 重要な状態変更の場合のみsendMessageも使う
            if force && session.isReachable && (state == "running" || state == "ended" || state == "idle") {
                session.sendMessage(phoneContext, replyHandler: nil, errorHandler: nil)
            }
        } catch {
            // エラーは記録するが、クラッシュさせない
            if elapsedSinceLast >= 10.0 { // エラーログも頻度制限
                print("Watch: Failed to update context: \(error.localizedDescription)")
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
