import Foundation
import WatchConnectivity
import Combine

enum WatchWorkoutState: String {
    case idle
    case running
    case paused
    case ended
}

enum WatchMessageType: String {
    case command = "command"
    case exerciseChange = "exerciseChange"
    case phaseChange = "phaseChange"
    case wakeUp = "wakeUp"
    case heartRate = "heartRate"
    case workoutState = "workoutState"
    case cycleIndex = "cycleIndex"
}

class WatchConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    @Published var watchHeartRate: Double = 0
    @Published var isWatchConnected: Bool = false
    @Published var watchStatus: String = "未接続"
    @Published var lastMessageTime: Date?
    @Published var watchWorkoutState: WatchWorkoutState = .idle
    @Published var watchElapsedTime: TimeInterval = 0
    @Published var watchElapsedTimeString: String = "00:00"
    @Published var currentExercise: (category: String, name: String)?

    private var session: WCSession?
    private let heartRateSubject = PassthroughSubject<Double, Never>()
    private var watchAvailabilityHandler: ((Bool) -> Void)?
    private var watchCheckTimer: Timer?

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    private override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
            print("iPhone: WCSession activated")

            // 起動直後に既存のapplicationContextをチェック
            if let currentSession = session, !currentSession.applicationContext.isEmpty {
                print("iPhone: 🚀 Found existing applicationContext during setup")
                processApplicationContext(currentSession.applicationContext)
            }

            // アプリ起動時にWatchを自動起動（バックグラウンドで）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.wakeUpWatch()
            }
        }
    }

    // MARK: - Send Commands to Watch

    func sendCommandToWatch(_ command: String) {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.command.rawValue,
            "command": command,
            "timestamp": Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("iPhone: Failed to send command \(command): \(error)")
            }
            print("iPhone: Sent command to watch: \(command)")
        } else {
            print("iPhone: Watch is not reachable, queuing command")
            do {
                var context = session.applicationContext
                context["lastCommand"] = command
                context["timestamp"] = Date().timeIntervalSince1970
                try session.updateApplicationContext(context)
            } catch {
                print("iPhone: Failed to update application context: \(error)")
            }
            watchStatus = "Watch未接続"
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

    // MARK: - New Methods for Enhanced Communication

    func wakeUpWatch() {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.wakeUp.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        if session.isReachable {
            // 高優先度メッセージとして送信
            session.sendMessage(message, replyHandler: { response in
                print("iPhone: Watch woke up successfully: \(response)")
                DispatchQueue.main.async {
                    self.watchStatus = "Watch起動済み"
                }
            }) { error in
                print("iPhone: Failed to wake up watch: \(error)")
            }
        } else {
            // アプリケーションコンテキストでも送信
            do {
                var context = session.applicationContext
                context["wakeUp"] = true
                context["timestamp"] = Date().timeIntervalSince1970
                try session.updateApplicationContext(context)
            } catch {
                print("iPhone: Failed to update wake up context: \(error)")
            }
        }
    }

    func sendExerciseChange(category: String, exercise: String) {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.exerciseChange.rawValue,
            "category": category,
            "exercise": exercise,
            "timestamp": Date().timeIntervalSince1970
        ]

        currentExercise = (category: category, name: exercise)

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("iPhone: Failed to send exercise change: \(error)")
            }
        }

        // Always update application context for persistence
        do {
            var context = session.applicationContext
            context["currentCategory"] = category
            context["currentExercise"] = exercise
            context["timestamp"] = Date().timeIntervalSince1970
            try session.updateApplicationContext(context)
        } catch {
            print("iPhone: Failed to update exercise context: \(error)")
        }
    }

    func sendPhaseChange(phase: String, cycleIndex: Int) {
        guard let session = session else { return }

        let message: [String: Any] = [
            "type": WatchMessageType.phaseChange.rawValue,
            "phase": phase,
            "cycleIndex": cycleIndex,
            "timestamp": Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("iPhone: Failed to send phase change: \(error)")
            }
        }
    }

    func checkWatchAvailability(completion: @escaping (Bool) -> Void) {
        guard let session = session else {
            completion(false)
            return
        }

        watchAvailabilityHandler = completion

        // 即座にreachableをチェック
        if session.isReachable {
            completion(true)
            watchAvailabilityHandler = nil
            return
        }

        // pingメッセージを送信してタイムアウトをチェック
        let pingMessage: [String: Any] = ["type": "ping", "timestamp": Date().timeIntervalSince1970]

        // タイムアウトタイマーを設定（3秒）
        watchCheckTimer?.invalidate()
        watchCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if let handler = self.watchAvailabilityHandler {
                handler(false)
                self.watchAvailabilityHandler = nil
            }
        }

        session.sendMessage(pingMessage, replyHandler: { response in
            self.watchCheckTimer?.invalidate()
            if let handler = self.watchAvailabilityHandler {
                handler(true)
                self.watchAvailabilityHandler = nil
            }
        }) { error in
            self.watchCheckTimer?.invalidate()
            if let handler = self.watchAvailabilityHandler {
                handler(false)
                self.watchAvailabilityHandler = nil
            }
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("iPhone: WCSession activation failed: \(error)")
            DispatchQueue.main.async {
                self.watchStatus = "接続エラー"
            }
        } else {
            print("iPhone: WCSession activated with state: \(activationState.rawValue)")

            // 既存のapplicationContextをチェック（Watch側のワークアウト状態を復元）
            if !session.applicationContext.isEmpty {
                print("iPhone: 📋 Checking existing applicationContext on activation...")
                processApplicationContext(session.applicationContext)
            }

            DispatchQueue.main.async {
                self.isWatchConnected = session.isReachable
                self.watchStatus = session.isReachable ? "Watch接続済み" : "Watch待機中"
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("iPhone: WCSession became inactive")
        DispatchQueue.main.async {
            self.isWatchConnected = false
            self.watchStatus = "非アクティブ"
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("iPhone: WCSession deactivated")
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("iPhone: 🔄 Watch reachability changed: \(session.isReachable)")

        // Watchが接続可能になった時に、保留中のコマンドをチェック
        if session.isReachable && !session.applicationContext.isEmpty {
            print("iPhone: 📥 Checking applicationContext on reachability change...")
            processApplicationContext(session.applicationContext)
        }

        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
            self.watchStatus = session.isReachable ? "Watch接続済み" : "Watch切断"
        }
    }

    // MARK: - Receive Data from Watch

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("iPhone: Received message from Watch: \(message)")
        handleIncomingPayload(message)

        // Watch側に確認応答を送信（可能な場合）
        if session.isReachable {
            let reply: [String: Any] = [
                "status": "received",
                "timestamp": Date().timeIntervalSince1970
            ]
            session.sendMessage(reply, replyHandler: nil) { error in
                print("iPhone: Failed to send acknowledgment to Watch: \(error)")
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("iPhone: Received message from Watch with reply handler")

        // pingメッセージへの応答
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["type": "pong", "timestamp": Date().timeIntervalSince1970])
            return
        }

        handleIncomingPayload(message)
        replyHandler(["received": true, "timestamp": Date().timeIntervalSince1970])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("iPhone: ⚡️ Received application context update")
        print("iPhone: Context keys: \(applicationContext.keys.sorted())")
        print("iPhone: Full context: \(applicationContext)")

        // 統一された処理関数を使用
        processApplicationContext(applicationContext)
    }

    // MARK: - Helpers

    private func processApplicationContext(_ context: [String: Any]) {
        print("iPhone: 🔍 Processing applicationContext: \(context.keys.sorted())")

        // コマンドタイプのメッセージをチェック
        if let type = context["type"] as? String, type == "command",
           let command = context["lastCommand"] as? String {
            print("iPhone: 🎯 Found command in applicationContext: '\(command)'")

            // タイムスタンプをチェック（古すぎるコマンドは実行しない）
            var shouldExecute = true
            if let timestamp = context["commandTimestamp"] as? TimeInterval {
                let commandAge = Date().timeIntervalSince(Date(timeIntervalSince1970: timestamp))
                if commandAge < 300 { // 5分以内のコマンドのみ実行
                    print("iPhone: ⏰ Command is recent (\(Int(commandAge))s old), executing...")
                    shouldExecute = true
                } else {
                    print("iPhone: ⚠️ Command is too old (\(Int(commandAge))s), skipping")
                    shouldExecute = false
                }
            }

            if shouldExecute {
                DispatchQueue.main.async { [weak self] in
                    self?.handleWatchCommand(command)
                    self?.lastMessageTime = Date()
                }
            }
        }

        // ワークアウト状態もチェック
        if let workoutState = context["workoutState"] as? String {
            print("iPhone: 🏃 Watch workout state: \(workoutState)")
            if workoutState == "running" || workoutState == "work" || workoutState == "rest" {
                // Watchでワークアウトが実行中の場合、iPhoneでも開始
                print("iPhone: 🚀 Auto-starting session based on Watch state")
                DispatchQueue.main.async {
                    if SessionManager.shared.currentPhase == .idle {
                        SessionManager.shared.startSession()
                    }
                }
            }
        }
    }

    private func handleIncomingPayload(_ payload: [String: Any]) {
        // センサーデータなど大きなペイロードは別スレッドで処理
        if let type = payload["type"] as? String, type == "sensor_data" {
            DispatchQueue.global(qos: .background).async { [weak self] in
                // センサーデータを処理（メモリリークを防ぐため weak self を使用）
                guard let self = self else { return }
                // SensorLogManagerに処理を委譲
                if let samples = payload["samples"] as? [[String: Any]] {
                    print("iPhone: Processing \(samples.count) sensor samples in background")
                }

                DispatchQueue.main.async { [weak self] in
                    self?.lastMessageTime = Date()
                }
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isWatchConnected = true

            if let timestamp = payload["timestamp"] as? TimeInterval {
                self.lastMessageTime = Date(timeIntervalSince1970: timestamp)
            } else {
                self.lastMessageTime = Date()
            }

            // メッセージタイプによって処理を分岐
            if let type = payload["type"] as? String {
                switch type {
                case WatchMessageType.heartRate.rawValue:
                    if let heartRate = payload["heartRate"] as? Double {
                        self.watchHeartRate = heartRate
                        self.heartRateSubject.send(heartRate)
                        self.watchStatus = "HR: \(Int(heartRate))"
                    }

                case WatchMessageType.workoutState.rawValue:
                    if let stateString = payload["state"] as? String,
                       let state = WatchWorkoutState(rawValue: stateString) {
                        self.watchWorkoutState = state
                        self.watchStatus = self.statusDescription(for: state)
                    }

                case WatchMessageType.phaseChange.rawValue:
                    // Watchから運動/休憩の切り替えリクエストが来た場合
                    if let requestedPhase = payload["requestedPhase"] as? String {
                        self.handleWatchPhaseChangeRequest(phase: requestedPhase)
                    }

                case WatchMessageType.exerciseChange.rawValue:
                    // Watchから種目変更リクエストが来た場合
                    if payload["requestChange"] as? Bool == true {
                        self.handleWatchExerciseChangeRequest()
                    }

                case WatchMessageType.command.rawValue:
                    // Watchからのコマンド処理
                    print("iPhone: 📨 Received command message via direct sendMessage")
                    if let command = payload["command"] as? String {
                        print("iPhone: 🎯 Command string found: '\(command)'")
                        self.handleWatchCommand(command)
                        self.watchStatus = "Command: \(command)"
                    } else {
                        print("iPhone: ⚠️ Received command message but no command string found")
                        print("iPhone: Payload keys: \(payload.keys)")
                    }

                default:
                    break
                }
            } else {
                // 従来の処理（後方互換性のため）
                if let heartRate = payload["heartRate"] as? Double {
                    self.watchHeartRate = heartRate
                    self.heartRateSubject.send(heartRate)
                    self.watchStatus = "HR: \(Int(heartRate))"
                }

                if let elapsedTime = payload["elapsedTime"] as? TimeInterval {
                    self.watchElapsedTime = elapsedTime
                    self.watchElapsedTimeString = Self.formatTime(elapsedTime)
                }

                if let stateString = payload["workoutState"] as? String,
                   let state = WatchWorkoutState(rawValue: stateString) {
                    self.watchWorkoutState = state
                    if payload["heartRate"] == nil {
                        self.watchStatus = self.statusDescription(for: state)
                    }
                }
            }
        }
    }

    private func handleWatchPhaseChangeRequest(phase: String) {
        // SessionManagerに通知してフェーズ変更を実行
        if phase == "work" || phase == "rest" {
            SessionManager.shared.togglePhase()
        } else if phase == "start" {
            SessionManager.shared.startSession()
        } else if phase == "stop" {
            SessionManager.shared.endSession()
        }
    }

    private func handleWatchExerciseChangeRequest() {
        // UIで種目選択画面を表示するための通知を送信
        NotificationCenter.default.post(
            name: Notification.Name("ShowExerciseSelection"),
            object: nil
        )
    }

    private func handleWatchCommand(_ command: String) {
        print("iPhone: 🔧 handleWatchCommand called with: '\(command)'")

        // すでにメインキューにいる場合とそうでない場合を処理
        let executeCommand = {
            print("iPhone: 🚀 Executing command: '\(command)' on main thread")

            switch command {
            case "togglePhase":
                print("iPhone: 📱 Calling SessionManager.shared.togglePhase()")
                SessionManager.shared.togglePhase()
                print("iPhone: ✅ togglePhase() completed")

            case "startSession":
                print("iPhone: 📱 Calling SessionManager.shared.startSession()")
                SessionManager.shared.startSession()
                print("iPhone: ✅ startSession() completed")

            case "endSession":
                print("iPhone: 📱 Calling SessionManager.shared.endSession()")
                SessionManager.shared.endSession()
                print("iPhone: ✅ endSession() completed")

            case "showExerciseSelection":
                print("iPhone: 📮 Posting ShowExerciseSelection notification")
                NotificationCenter.default.post(
                    name: Notification.Name("ShowExerciseSelection"),
                    object: nil
                )
                print("iPhone: ✅ ShowExerciseSelection notification posted")

            default:
                print("iPhone: ❌ Unknown command from Watch: '\(command)'")
            }

            print("iPhone: 🏁 Command execution finished: '\(command)'")
        }

        if Thread.isMainThread {
            executeCommand()
        } else {
            DispatchQueue.main.async {
                executeCommand()
            }
        }
    }

    private func statusDescription(for state: WatchWorkoutState) -> String {
        switch state {
        case .idle: return "Watch待機中"
        case .running: return "Watch稼働中"
        case .paused: return "Watch一時停止"
        case .ended: return "Watch終了"
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%02d:%02d:%02d", hours, remainingMinutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}