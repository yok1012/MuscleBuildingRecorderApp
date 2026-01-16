import Foundation
import WatchConnectivity
import Combine

enum WatchWorkoutState: String {
    case idle = "idle"
    case running = "running"
    case paused = "paused"
    case ended = "ended"
}

enum WatchMessageType: String {
    case wakeUp = "wakeUp"
    case heartRate = "heartRate"
    case workoutState = "workoutState"
    case phaseChange = "phaseChange"
    case exerciseChange = "exerciseChange"
    case command = "command"
}

class WatchConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    // Watch経由の心拍数データ
    @Published var watchHeartRate: Double = 0
    @Published var isWatchConnected: Bool = false
    @Published var watchStatus: String = "未接続"
    @Published var lastMessageTime: Date?
    @Published var watchWorkoutState: WatchWorkoutState = .idle
    @Published var watchElapsedTime: TimeInterval = 0
    @Published var watchElapsedTimeString: String = "00:00"
    @Published var currentExercise: String = ""
    @Published var showExerciseSelectionRequested: Bool = false  // Watchから種目選択要求

    // 心拍数更新の通知用
    static let heartRateDidUpdateNotification = Notification.Name("WatchHeartRateDidUpdate")

    private var session: WCSession?
    private var watchAvailabilityHandler: ((Bool) -> Void)?
    private var lastProcessedCommandId: String?

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        guard WCSession.isSupported() else {
            print("iPhone: WCSession is not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()

        // DEBUG: セッション設定確認（問題解決後削除）
        #if DEBUG
        print("📱 iPhone: WCSession setup complete - delegate: \(String(describing: session?.delegate))")
        #endif

        // 初期コンテキストの処理
        if let currentSession = session, !currentSession.applicationContext.isEmpty {
            processApplicationContext(currentSession.applicationContext)
        }
    }

    // MARK: - Send Commands to Watch

    func sendCommandToWatch(_ command: String) {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": "command",
            "command": command,
            "timestamp": Date().timeIntervalSince1970
        ]

        // applicationContextを更新（確実性のため）
        do {
            try session.updateApplicationContext(message)
        } catch {
            print("iPhone: Failed to update context: \(error.localizedDescription)")
        }

        // reachableな場合は即座に送信
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    func startWatchWorkout() {
        sendCommandToWatch("start")
    }

    func stopWatchWorkout() {
        sendCommandToWatch("stop")
    }

    func pauseWatchWorkout() {
        sendCommandToWatch("pause")
    }

    func resumeWatchWorkout() {
        sendCommandToWatch("resume")
    }

    /// iPhone側のWatch状態をリセット（セッション終了時に呼び出す）
    func resetWatchState() {
        DispatchQueue.main.async { [weak self] in
            self?.watchWorkoutState = .idle
            self?.watchElapsedTime = 0
            self?.watchElapsedTimeString = "00:00"
            self?.watchStatus = self?.isWatchConnected == true ? "接続済み" : "未接続"
        }
    }

    // MARK: - Enhanced Communication Methods

    func wakeUpWatch() {
        guard let session = session else { return }

        let wakeMessage: [String: Any] = [
            "type": WatchMessageType.wakeUp.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        // applicationContextを更新
        do {
            try session.updateApplicationContext(wakeMessage)
        } catch {
            print("iPhone: Failed to update context: \(error.localizedDescription)")
        }

        // reachableな場合は即座に送信
        if session.isReachable {
            session.sendMessage(wakeMessage, replyHandler: { _ in
                print("iPhone: Watch woke up successfully")
            }) { error in
                print("iPhone: Could not wake Watch: \(error.localizedDescription)")
            }
        }
    }

    func sendExerciseChange(category: String, exercise: String) {
        guard let session = session else { return }

        currentExercise = "\(category) - \(exercise)"

        let message: [String: Any] = [
            "type": WatchMessageType.exerciseChange.rawValue,
            "category": category,
            "exercise": exercise,
            "timestamp": Date().timeIntervalSince1970
        ]

        // applicationContextを更新
        do {
            var context = session.applicationContext
            context["currentCategory"] = category
            context["currentExercise"] = exercise
            try session.updateApplicationContext(context)
        } catch {
            print("iPhone: Failed to update exercise context: \(error.localizedDescription)")
        }

        // reachableな場合は即座に送信
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    func sendPhaseChange(phase: String, cycleIndex: Int,
                         totalWorkTime: TimeInterval, totalRestTime: TimeInterval,
                         elapsedTime: TimeInterval, currentPhaseTime: TimeInterval,
                         previousPhase: String?, previousPhaseDuration: TimeInterval?) {
        guard let session = session else { return }

        var message: [String: Any] = [
            "type": WatchMessageType.phaseChange.rawValue,
            "phase": phase,
            "cycleIndex": cycleIndex,
            "totalWorkTime": totalWorkTime,
            "totalRestTime": totalRestTime,
            "elapsedTime": elapsedTime,
            "currentPhaseTime": currentPhaseTime,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let previousPhase = previousPhase {
            message["previousPhase"] = previousPhase
        }
        if let previousPhaseDuration = previousPhaseDuration {
            message["previousPhaseDuration"] = previousPhaseDuration
        }

        // reachableな場合のみ送信（過剰な通信を防ぐ）
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    func checkWatchAvailability(completion: @escaping (Bool) -> Void) {
        guard let session = session else {
            completion(false)
            return
        }

        if session.isReachable {
            let pingMessage: [String: Any] = [
                "type": "ping",
                "timestamp": Date().timeIntervalSince1970
            ]

            session.sendMessage(pingMessage, replyHandler: { response in
                if response["type"] as? String == "pong" {
                    DispatchQueue.main.async {
                        completion(true)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }) { _ in
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        } else {
            completion(false)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("iPhone: Activation failed: \(error.localizedDescription)")
            return
        }

        if activationState == .activated {
            // DEBUG: アクティベーション確認（問題解決後削除）
            #if DEBUG
            print("📱 iPhone: WCSession activated - reachable: \(session.isReachable), paired: \(session.isPaired), installed: \(session.isWatchAppInstalled)")
            #endif

            DispatchQueue.main.async { [weak self] in
                self?.isWatchConnected = session.isReachable
                self?.watchStatus = session.isReachable ? "接続済み" : "待機中"
            }

            // 既存のコンテキストを処理
            if !session.applicationContext.isEmpty {
                processApplicationContext(session.applicationContext)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchConnected = false
            self?.watchStatus = "非アクティブ"
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            let isReachable = session.isReachable
            self?.isWatchConnected = isReachable
            self?.watchStatus = isReachable ? "接続済み" : "待機中"
            
            // HeartRateManagerにWatch接続状態の変化を通知
            NotificationCenter.default.post(
                name: NSNotification.Name("WatchReachabilityChanged"),
                object: nil,
                userInfo: ["isReachable": isReachable]
            )
        }
    }

    // MARK: - Receive Data from Watch

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // DEBUG: メッセージ受信確認（問題解決後削除）
        #if DEBUG
        print("📱 iPhone: Message received from Watch - type: \(message["type"] ?? "unknown"), command: \(message["command"] ?? "none")")
        #endif
        handleIncomingPayload(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // pingへの応答
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["type": "pong", "timestamp": Date().timeIntervalSince1970])
            return
        }

        // DEBUG: 返信付きメッセージ受信確認（問題解決後削除）
        #if DEBUG
        print("📱 iPhone: ReplyHandler message received - type: \(message["type"] ?? "unknown"), command: \(message["command"] ?? "none")")
        #endif

        handleIncomingPayload(message)
        replyHandler(["received": true, "timestamp": Date().timeIntervalSince1970])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        processApplicationContext(applicationContext)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if DEBUG
        print("📱 iPhone: Received file from Watch: \(file.fileURL)")
        #endif

        // JSONLファイル（センサーデータ）の処理
        if file.fileURL.lastPathComponent.contains("accel") &&
           file.fileURL.pathExtension == "jsonl" {
            SensorLogManager.shared.processJSONLFile(at: file.fileURL)
        }
    }

    // MARK: - Helper Methods

    private func processApplicationContext(_ context: [String: Any]) {
        #if DEBUG
        print("📱 iPhone: Processing applicationContext - keys: \(context.keys.sorted())")
        #endif

        // コマンドの処理（type=="command"またはlastCommandが存在する場合）
        let contextType = context["type"] as? String
        let hasCommand = contextType == "command" || context["lastCommand"] != nil || context["command"] != nil

        if hasCommand {
            let command = (context["lastCommand"] as? String) ?? (context["command"] as? String)
            let commandId = context["commandId"] as? String

            // 重複処理を防ぐ（commandIdがある場合のみ）
            let shouldProcess: Bool
            if let commandId = commandId {
                shouldProcess = commandId != lastProcessedCommandId
                if shouldProcess {
                    lastProcessedCommandId = commandId
                }
            } else {
                // commandIdがない場合は常に処理（後方互換性）
                shouldProcess = true
            }

            if let command = command, shouldProcess {
                #if DEBUG
                print("📱 iPhone: Processing command from context: '\(command)'")
                #endif

                let totalWorkTime = context["totalWorkTime"] as? TimeInterval ?? 0
                let totalRestTime = context["totalRestTime"] as? TimeInterval ?? 0
                let currentPhase = context["currentPhase"] as? String ?? "idle"
                let currentPhaseTime = context["currentPhaseTime"] as? TimeInterval
                let previousPhase = context["previousPhase"] as? String
                let previousPhaseDuration = context["previousPhaseDuration"] as? TimeInterval

                DispatchQueue.main.async { [weak self] in
                    self?.handleWatchCommandWithTimeSync(
                        command: command,
                        totalWorkTime: totalWorkTime,
                        totalRestTime: totalRestTime,
                        currentPhase: currentPhase,
                        currentPhaseTime: currentPhaseTime,
                        previousPhase: previousPhase,
                        previousPhaseDuration: previousPhaseDuration
                    )
                }
            }
        }

        // ワークアウト状態の処理
        if let stateString = context["workoutState"] as? String,
           let state = WatchWorkoutState(rawValue: stateString) {
            DispatchQueue.main.async { [weak self] in
                self?.watchWorkoutState = state
            }
        }

        // 時間データの同期（コマンド以外の場合のみ、フェーズは変更しない）
        // 重要: コマンド経由でない時間同期ではフェーズを変更しない
        // これは古いapplicationContextが新しいフェーズを上書きするのを防ぐ
        if !hasCommand && (context["totalWorkTime"] != nil || context["totalRestTime"] != nil) {
            let totalWorkTime = context["totalWorkTime"] as? TimeInterval ?? 0
            let totalRestTime = context["totalRestTime"] as? TimeInterval ?? 0
            // フェーズは同期しない（currentPhaseIdentifier: nil）
            // 時間データのみ同期する
            let currentPhaseTime = context["currentPhaseTime"] as? TimeInterval

            DispatchQueue.main.async {
                SessionManager.shared.syncTimeFromWatch(
                    totalWorkTime: totalWorkTime,
                    totalRestTime: totalRestTime,
                    currentPhaseIdentifier: nil,  // フェーズは変更しない
                    currentPhaseTime: currentPhaseTime
                )
            }
        }

        // Note: 心拍数はiPhone側でHealthKitから直接取得するため、
        // Watch経由の心拍データは処理しない（安定性向上のため）

        // 経過時間の処理
        if let elapsedTime = context["elapsedTime"] as? TimeInterval {
            DispatchQueue.main.async { [weak self] in
                self?.watchElapsedTime = elapsedTime
                self?.watchElapsedTimeString = self?.formatTime(elapsedTime) ?? "00:00"
            }
        }

        // エクササイズ情報の処理
        if let category = context["currentCategory"] as? String,
           let exercise = context["currentExercise"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.currentExercise = "\(category) - \(exercise)"
            }
        }

        // サイクルインデックスの処理
        if let cycleIndex = context["cycleIndex"] as? Int {
            DispatchQueue.main.async {
                SessionManager.shared.cycleIndex = cycleIndex
            }
        }
    }

    // 注意: WatchConnectivityServiceが唯一のWCSessionDelegateなので、
    // 転送メソッド(handleMessageFromWatch, handleApplicationContextFromWatch)は不要になりました。
    // SensorLogManagerはWCSessionDelegateを実装せず、直接呼び出しでデータを受け取ります。

    private func handleIncomingPayload(_ payload: [String: Any]) {
        // センサーデータはSensorLogManagerに転送
        if let type = payload["type"] as? String,
           (type == "sensor_data" || type == "accel"),
           let samples = payload["samples"] as? [[String: Any]] {
            let sensors = payload["sensors"] as? [String] ?? ["accel"]
            SensorLogManager.shared.processSensorData(samples: samples, sensors: sensors)
            DispatchQueue.main.async { [weak self] in
                self?.lastMessageTime = Date()
            }
            return
        }

        // 旧形式の加速度データ（互換性のため）
        if let type = payload["type"] as? String, type == "accel",
           let samples = payload["samples"] as? [[Any]] {
            let convertedSamples = samples.compactMap { sample -> [String: Any]? in
                guard sample.count >= 4,
                      let t = sample[0] as? Int64,
                      let ax = sample[1] as? Double,
                      let ay = sample[2] as? Double,
                      let az = sample[3] as? Double else { return nil }
                return ["t": t, "ax": ax, "ay": ay, "az": az]
            }
            SensorLogManager.shared.processSensorData(samples: convertedSamples, sensors: ["accel"])
            DispatchQueue.main.async { [weak self] in
                self?.lastMessageTime = Date()
            }
            return
        }

        // ステータスメッセージの処理
        if let status = payload["status"] as? String {
            SensorLogManager.shared.updateLoggingStatus(status)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isWatchConnected = true
            self.lastMessageTime = Date()

            // メッセージタイプによる処理
            if let type = payload["type"] as? String {
                switch type {
                case WatchMessageType.heartRate.rawValue:
                    // Watch経由の心拍データを処理
                    if let heartRate = payload["heartRate"] as? Double, heartRate > 0 {
                        self.watchHeartRate = heartRate
                        self.watchStatus = "\(Int(heartRate)) BPM"
                        // HeartRateManagerに通知
                        NotificationCenter.default.post(
                            name: WatchConnectivityService.heartRateDidUpdateNotification,
                            object: nil,
                            userInfo: ["heartRate": heartRate]
                        )
                    }

                case WatchMessageType.workoutState.rawValue:
                    // ワークアウト状態の処理
                    self.processWorkoutStateMessage(payload)
                    
                case "syncSession":
                    // Watchからの完了済みセッション同期
                    self.handleSyncSessionFromWatch(payload)
                    
                case "syncState":
                    // Watchからの現在状態同期（スタンドアロンモードからの復帰）
                    self.handleSyncStateFromWatch(payload)

                case WatchMessageType.command.rawValue:
                    if let command = payload["command"] as? String {
                        // コマンドIDによる重複処理防止
                        let commandId = payload["commandId"] as? String
                        let shouldProcess: Bool
                        if let commandId = commandId {
                            shouldProcess = commandId != self.lastProcessedCommandId
                            if shouldProcess {
                                self.lastProcessedCommandId = commandId
                            }
                        } else {
                            shouldProcess = true
                        }

                        guard shouldProcess else {
                            #if DEBUG
                            print("📱 iPhone: Skipping duplicate command '\(command)'")
                            #endif
                            return
                        }

                        #if DEBUG
                        print("📱 iPhone: Processing command '\(command)' from Watch (sendMessage)")
                        #endif

                        let totalWorkTime = payload["totalWorkTime"] as? TimeInterval ?? 0
                        let totalRestTime = payload["totalRestTime"] as? TimeInterval ?? 0
                        let currentPhase = payload["currentPhase"] as? String ?? "idle"
                        let currentPhaseTime = payload["currentPhaseTime"] as? TimeInterval
                        let previousPhase = payload["previousPhase"] as? String
                        let previousPhaseDuration = payload["previousPhaseDuration"] as? TimeInterval

                        self.handleWatchCommandWithTimeSync(
                            command: command,
                            totalWorkTime: totalWorkTime,
                            totalRestTime: totalRestTime,
                            currentPhase: currentPhase,
                            currentPhaseTime: currentPhaseTime,
                            previousPhase: previousPhase,
                            previousPhaseDuration: previousPhaseDuration
                        )
                        self.watchStatus = command

                        // コマンド確認応答を送信
                        self.sendCommandAck(command: command, success: true)
                    }

                default:
                    // その他のメッセージタイプの処理
                    self.processLegacyMessage(payload)
                }
            } else {
                // 従来のメッセージ形式の処理
                self.processLegacyMessage(payload)
            }
        }
    }

    // MARK: - Watch Sync Handlers
    
    /// Watchからの完了済みセッションデータを同期
    private func handleSyncSessionFromWatch(_ payload: [String: Any]) {
        guard let sessionIdString = payload["sessionId"] as? String,
              let startTimeInterval = payload["startTime"] as? TimeInterval,
              let endTimeInterval = payload["endTime"] as? TimeInterval,
              let totalWorkTime = payload["totalWorkTime"] as? TimeInterval,
              let totalRestTime = payload["totalRestTime"] as? TimeInterval else {
            print("📱 iPhone: Invalid syncSession payload")
            return
        }
        
        print("📱 iPhone: Received sync session from Watch: \(sessionIdString)")
        print("📱 iPhone: Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")
        
        // SessionManagerに通知してCore Dataに保存
        // Note: 既に存在するセッションとの重複チェックが必要
        NotificationCenter.default.post(
            name: NSNotification.Name("WatchSessionSyncReceived"),
            object: nil,
            userInfo: [
                "sessionId": sessionIdString,
                "startTime": Date(timeIntervalSince1970: startTimeInterval),
                "endTime": Date(timeIntervalSince1970: endTimeInterval),
                "totalWorkTime": totalWorkTime,
                "totalRestTime": totalRestTime
            ]
        )
        
        // 成功応答を送信
        if let session = session, session.isReachable {
            session.sendMessage(
                ["type": "syncAck", "sessionId": sessionIdString, "success": true],
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }
    
    /// Watchからの現在状態を同期（スタンドアロンモードからの復帰時）
    private func handleSyncStateFromWatch(_ payload: [String: Any]) {
        let totalWorkTime = payload["totalWorkTime"] as? TimeInterval ?? 0
        let totalRestTime = payload["totalRestTime"] as? TimeInterval ?? 0
        let currentPhase = payload["currentPhase"] as? String ?? "work"
        let currentPhaseTime = payload["currentPhaseTime"] as? TimeInterval ?? 0
        let elapsedTime = payload["elapsedTime"] as? TimeInterval ?? (totalWorkTime + totalRestTime)
        
        print("📱 iPhone: Syncing state from Watch standalone mode")
        print("📱 iPhone: Phase: \(currentPhase), Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")
        
        // SessionManagerがアクティブでない場合、セッションを開始
        let sessionManager = SessionManager.shared
        if sessionManager.currentPhase == .idle {
            print("📱 iPhone: Starting session from Watch sync")
            sessionManager.startSessionWithTimeSync(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime
            )
        }
        
        // 時間を同期
        sessionManager.syncTimeFromWatch(
            totalWorkTime: totalWorkTime,
            totalRestTime: totalRestTime,
            currentPhaseIdentifier: currentPhase,
            currentPhaseTime: currentPhaseTime,
            completedPhaseIdentifier: nil,
            completedPhaseDuration: nil
        )
        
        watchStatus = "同期完了"
    }

    private func processWorkoutStateMessage(_ payload: [String: Any]) {
        // ワークアウト状態の処理
        if let stateString = payload["workoutState"] as? String,
           let state = WatchWorkoutState(rawValue: stateString) {
            watchWorkoutState = state
            if payload["heartRate"] == nil {
                watchStatus = statusDescription(for: state)
            }
        }

        // 時間データの同期（フェーズは変更しない）
        // 重要: タイマー更新からのフェーズ変更は行わない
        // フェーズ変更は明示的なコマンド(togglePhase等)経由でのみ行う
        if let totalWorkTime = payload["totalWorkTime"] as? TimeInterval,
           let totalRestTime = payload["totalRestTime"] as? TimeInterval {
            SessionManager.shared.syncTimeFromWatch(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                currentPhaseIdentifier: nil,  // フェーズは変更しない
                currentPhaseTime: payload["currentPhaseTime"] as? TimeInterval,
                completedPhaseIdentifier: nil,
                completedPhaseDuration: nil
            )
        }

        // 経過時間の処理
        if let elapsedTime = payload["elapsedTime"] as? TimeInterval {
            watchElapsedTime = elapsedTime
            watchElapsedTimeString = formatTime(elapsedTime)
        }

        // Note: 心拍数はiPhone側でHealthKitから直接取得するため、
        // Watch経由の心拍データは処理しない（安定性向上のため）
    }

    /// コマンド確認応答をWatchに送信
    private func sendCommandAck(command: String, success: Bool) {
        guard let session = session, session.isReachable else { return }

        let ack: [String: Any] = [
            "type": "commandAck",
            "command": command,
            "success": success,
            "timestamp": Date().timeIntervalSince1970
        ]
        session.sendMessage(ack, replyHandler: nil, errorHandler: nil)
    }

    private func processLegacyMessage(_ payload: [String: Any]) {
        // Note: 心拍数はiPhone側でHealthKitから直接取得するため、
        // Watch経由の心拍データは処理しない（安定性向上のため）

        // 経過時間の処理
        if let elapsedTime = payload["elapsedTime"] as? TimeInterval {
            watchElapsedTime = elapsedTime
            watchElapsedTimeString = formatTime(elapsedTime)
        }

        // 時間データの同期（フェーズは変更しない）
        // 重要: レガシーメッセージからフェーズ変更は行わない
        if let totalWorkTime = payload["totalWorkTime"] as? TimeInterval,
           let totalRestTime = payload["totalRestTime"] as? TimeInterval {
            SessionManager.shared.syncTimeFromWatch(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                currentPhaseIdentifier: nil,  // フェーズは変更しない
                currentPhaseTime: payload["currentPhaseTime"] as? TimeInterval
            )
        }

        // ワークアウト状態の処理
        if let stateString = payload["workoutState"] as? String,
           let state = WatchWorkoutState(rawValue: stateString) {
            watchWorkoutState = state
            if payload["heartRate"] == nil {
                watchStatus = statusDescription(for: state)
            }
        }
    }

    private func handleWatchPhaseChangeRequest(phase: String) {
        // フェーズ変更リクエストの処理
        print("iPhone: Phase change requested: \(phase)")
    }

    private func handleWatchExerciseChangeRequest() {
        // エクササイズ変更リクエストの処理
        print("iPhone: Exercise change requested from Watch")
        DispatchQueue.main.async { [weak self] in
            self?.showExerciseSelectionRequested = true
        }
    }

    private func handleWatchCommandWithTimeSync(command: String,
                                                totalWorkTime: TimeInterval,
                                                totalRestTime: TimeInterval,
                                                currentPhase: String,
                                                currentPhaseTime: TimeInterval?,
                                                previousPhase: String?,
                                                previousPhaseDuration: TimeInterval?) {
        let sessionManager = SessionManager.shared

        // DEBUG: コマンド実行確認（問題解決後削除）
        #if DEBUG
        print("📱 iPhone: Executing command '\(command)', current phase: \(sessionManager.currentPhase)")
        #endif

        switch command {
        case "startSession":
            if sessionManager.currentPhase == .idle {
                if totalWorkTime > 0 || totalRestTime > 0 {
                    sessionManager.startSessionWithTimeSync(
                        totalWorkTime: totalWorkTime,
                        totalRestTime: totalRestTime
                    )
                } else {
                    sessionManager.startSession()
                }
                #if DEBUG
                print("📱 iPhone: Started session")
                #endif
            }

        case "endSession":
            if sessionManager.currentPhase != .idle {
                sessionManager.endSession()
                #if DEBUG
                print("📱 iPhone: Ended session")
                #endif
            }

        case "togglePhase":
            // まず時間データを同期（フェーズは変更しない）
            sessionManager.syncTimeFromWatch(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                currentPhaseIdentifier: nil,  // フェーズは下で適用するので、ここでは設定しない
                currentPhaseTime: currentPhaseTime,
                completedPhaseIdentifier: previousPhase,
                completedPhaseDuration: previousPhaseDuration
            )
            // Watchが指定したフェーズを適用（Watchには通知しない）
            // currentPhaseはWatchの「新しい」フェーズ（トグル後の状態）
            sessionManager.applyPhaseChangeFromWatch(
                newPhaseIdentifier: currentPhase,
                previousPhaseIdentifier: previousPhase,
                previousPhaseDuration: previousPhaseDuration
            )
            #if DEBUG
            print("📱 iPhone: Applied phase from Watch: \(currentPhase) → iPhone now: \(sessionManager.currentPhase)")
            #endif

        case "showExerciseSelection":
            handleWatchExerciseChangeRequest()

        default:
            break
        }
    }

    private func statusDescription(for state: WatchWorkoutState) -> String {
        switch state {
        case .idle: return "待機中"
        case .running: return "実行中"
        case .paused: return "一時停止"
        case .ended: return "終了"
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
