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

    @Published var watchHeartRate: Double = 0.0
    @Published var isWatchConnected: Bool = false
    @Published var watchStatus: String = "未接続"
    @Published var lastMessageTime: Date?
    @Published var watchWorkoutState: WatchWorkoutState = .idle
    @Published var watchElapsedTime: TimeInterval = 0
    @Published var watchElapsedTimeString: String = "00:00"
    @Published var currentExercise: String = ""

    private var session: WCSession?
    private let heartRateSubject = PassthroughSubject<Double, Never>()
    private var watchAvailabilityHandler: ((Bool) -> Void)?
    private var lastProcessedCommandId: String?
    private var lastHeartRateUpdate: Date = Date()
    private var messageThrottleTimer: Timer?

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

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
            self?.isWatchConnected = session.isReachable
            self?.watchStatus = session.isReachable ? "接続済み" : "待機中"
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

    // MARK: - Helper Methods

    private func processApplicationContext(_ context: [String: Any]) {
        // コマンドの処理
        if context["type"] as? String == "command",
           let command = context["lastCommand"] as? String,
           let commandId = context["commandId"] as? String {

            // 重複処理を防ぐ
            if commandId != lastProcessedCommandId {
                lastProcessedCommandId = commandId

                let totalWorkTime = context["totalWorkTime"] as? TimeInterval ?? 0
                let totalRestTime = context["totalRestTime"] as? TimeInterval ?? 0
                let currentPhase = context["currentPhase"] as? String ?? "idle"
                let currentPhaseTime = context["currentPhaseTime"] as? TimeInterval
                let previousPhase = context["previousPhase"] as? String
                let previousPhaseDuration = context["previousPhaseDuration"] as? TimeInterval

                handleWatchCommandWithTimeSync(
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

    private func handleIncomingPayload(_ payload: [String: Any]) {
        // センサーデータは別スレッドで処理
        if let type = payload["type"] as? String, type == "sensor_data" {
            DispatchQueue.global(qos: .background).async { [weak self] in
                // センサーデータの処理
                self?.lastMessageTime = Date()
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isWatchConnected = true
            self.lastMessageTime = Date()

            // メッセージタイプによる処理
            if let type = payload["type"] as? String {
                switch type {
                case WatchMessageType.heartRate.rawValue:
                    // 心拍数の更新頻度を制限（1秒に1回まで）
                    let now = Date()
                    if now.timeIntervalSince(self.lastHeartRateUpdate) >= 1.0 {
                        if let heartRate = payload["heartRate"] as? Double {
                            self.watchHeartRate = heartRate
                            self.heartRateSubject.send(heartRate)
                            self.watchStatus = "HR: \(Int(heartRate))"
                            self.lastHeartRateUpdate = now
                        }
                    }

                case WatchMessageType.command.rawValue:
                    if let command = payload["command"] as? String {
                        // DEBUG: コマンド処理確認（問題解決後削除）
                        #if DEBUG
                        print("📱 iPhone: Processing command '\(command)' from Watch")
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

    private func processLegacyMessage(_ payload: [String: Any]) {
        // 心拍数の処理
        if let heartRate = payload["heartRate"] as? Double {
            let now = Date()
            if now.timeIntervalSince(lastHeartRateUpdate) >= 1.0 {
                watchHeartRate = heartRate
                heartRateSubject.send(heartRate)
                lastHeartRateUpdate = now
            }
        }

        // 経過時間の処理
        if let elapsedTime = payload["elapsedTime"] as? TimeInterval {
            watchElapsedTime = elapsedTime
            watchElapsedTimeString = formatTime(elapsedTime)
        }

        // 時間データの同期
        if let totalWorkTime = payload["totalWorkTime"] as? TimeInterval,
           let totalRestTime = payload["totalRestTime"] as? TimeInterval {
            SessionManager.shared.syncTimeFromWatch(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                currentPhaseIdentifier: payload["currentPhase"] as? String,
                currentPhaseTime: payload["currentPhaseTime"] as? TimeInterval,
                completedPhaseIdentifier: payload["previousPhase"] as? String,
                completedPhaseDuration: payload["previousPhaseDuration"] as? TimeInterval
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
        print("iPhone: Exercise change requested")
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
            sessionManager.syncTimeFromWatch(
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                currentPhaseIdentifier: currentPhase,
                currentPhaseTime: currentPhaseTime,
                completedPhaseIdentifier: previousPhase,
                completedPhaseDuration: previousPhaseDuration
            )
            sessionManager.togglePhase()
            #if DEBUG
            print("📱 iPhone: Toggled phase to \(sessionManager.currentPhase)")
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