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
    private var contextCheckTimer: Timer?
    private var lastProcessedCommandId: String?

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    private override init() {
        super.init()
        setupSession()

        // デリゲートが確実に設定されていることを確認
        DispatchQueue.main.async { [weak self] in
            self?.verifyDelegateSetup()
        }
    }

    private func setupSession() {
        print("iPhone: 🔧 WatchConnectivityService.setupSession() called")
        if WCSession.isSupported() {
            session = WCSession.default

            // デリゲート設定前に現在のデリゲートを確認
            if session?.delegate != nil && !(session?.delegate is WatchConnectivityService) {
                print("iPhone: ⚠️ WARNING: WCSession delegate was already set to another object!")
                print("iPhone: Current delegate: \(String(describing: session?.delegate))")
            }

            session?.delegate = self
            session?.activate()
            print("iPhone: ✅ WCSession.default activated, delegate set to WatchConnectivityService")
            print("iPhone: 🔍 Delegate verification: \(session?.delegate === self ? "✅ Correct" : "❌ Incorrect")")

            // 起動直後に既存のapplicationContextをチェック
            if let currentSession = session, !currentSession.applicationContext.isEmpty {
                print("iPhone: 🚀 Found existing applicationContext during setup:")
                print("iPhone: Context keys: \(currentSession.applicationContext.keys.sorted())")
                processApplicationContext(currentSession.applicationContext)
            } else {
                print("iPhone: 📭 No existing applicationContext found during setup")
            }

            // アプリ起動時にWatchを自動起動（バックグラウンドで）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                print("iPhone: 🔄 Attempting to wake up Watch (1s after setup)")
                self?.wakeUpWatch()
            }

            // 定期的にapplicationContextをチェック（コマンド見逃し対策）
            print("iPhone: ⏱️ Starting context monitoring timer")
            startContextMonitoring()
        } else {
            print("iPhone: ❌ WCSession is not supported on this device")
        }
    }

    private func startContextMonitoring() {
        // 既存のタイマーをクリア
        contextCheckTimer?.invalidate()

        // 2秒ごとにapplicationContextをチェック
        contextCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let session = self.session else { return }

            if !session.applicationContext.isEmpty {
                // commandIdが存在する場合、変化をチェック
                if let commandId = session.applicationContext["commandId"] as? String {
                    // 初回またはcommandIdが変わった場合に処理
                    if self.lastProcessedCommandId == nil || commandId != self.lastProcessedCommandId {
                        print("iPhone: 🔍 Detected command in applicationContext (ID: \(commandId))")
                        self.processApplicationContext(session.applicationContext)
                        self.lastProcessedCommandId = commandId
                    }
                } else if session.applicationContext["lastCommand"] != nil {
                    // commandIdがない古い形式のコマンドも処理（後方互換性）
                    print("iPhone: 🔍 Detected legacy command in applicationContext")
                    self.processApplicationContext(session.applicationContext)
                }
            }
        }
    }
    
    deinit {
        contextCheckTimer?.invalidate()
        watchCheckTimer?.invalidate()
    }

    private func sendHeartbeatToWatch() {
        guard let session = session, session.isReachable else { return }

        let heartbeat: [String: Any] = [
            "type": "heartbeat",
            "timestamp": Date().timeIntervalSince1970,
            "message": "iPhone is ready to receive commands"
        ]

        session.sendMessage(heartbeat, replyHandler: { response in
            print("iPhone: 💚 Heartbeat acknowledged by Watch: \(response)")
        }) { error in
            print("iPhone: 💔 Heartbeat failed: \(error)")
        }
    }

    private func verifyDelegateSetup() {
        print("iPhone: 🔍 Verifying WCSession delegate setup...")
        guard let session = self.session else {
            print("iPhone: ❌ ERROR: WCSession is nil!")
            return
        }

        if session.delegate === self {
            print("iPhone: ✅ SUCCESS: Delegate is correctly set to WatchConnectivityService")
            print("iPhone: 📱 Activation state: \(session.activationState.rawValue) (0=notActivated, 1=inactive, 2=activated)")
            print("iPhone: 📲 Is paired: \(session.isPaired)")
            print("iPhone: ⌚ Watch app installed: \(session.isWatchAppInstalled)")
            print("iPhone: 🔗 Is reachable: \(session.isReachable)")

            // アクティベーションが完了していない場合は再試行
            if session.activationState != .activated {
                print("iPhone: ⚠️ Session not fully activated. Re-activating...")
                session.activate()
            }
        } else {
            print("iPhone: ❌ ERROR: Delegate is NOT set to WatchConnectivityService!")
            print("iPhone: Current delegate: \(String(describing: session.delegate))")

            // デリゲートを再設定
            print("iPhone: 🔧 Attempting to reset delegate...")
            session.delegate = self
            session.activate()
            print("iPhone: ✅ Delegate reset and session re-activated")
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
            "timestamp": Date().timeIntervalSince1970,
            "urgent": true
        ]

        print("iPhone: 🚀 Attempting to wake up Watch app...")

        // アプリケーションコンテキストを先に更新（確実性を高める）
        do {
            var context = session.applicationContext
            context["wakeUp"] = true
            context["wakeUpCommand"] = "start"
            context["timestamp"] = Date().timeIntervalSince1970
            try session.updateApplicationContext(context)
            print("iPhone: 💾 Wake up context saved to applicationContext")
        } catch {
            print("iPhone: ⚠️ Failed to update wake up context: \(error)")
        }

        // リアルタイムメッセージも送信
        if session.isReachable {
            // 高優先度メッセージとして送信
            session.sendMessage(message, replyHandler: { response in
                print("iPhone: ✅ Watch woke up successfully: \(response)")
                DispatchQueue.main.async {
                    self.watchStatus = "Watch起動済み"
                }
            }) { error in
                print("iPhone: ⚠️ Failed to wake up watch via message: \(error)")
            }
        } else {
            print("iPhone: 📵 Watch not reachable, relying on applicationContext")
            DispatchQueue.main.async {
                self.watchStatus = "Watch起動待機中"
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

    func sendPhaseChange(
        phase: String,
        cycleIndex: Int,
        totalWorkTime: TimeInterval? = nil,
        totalRestTime: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        currentPhaseTime: TimeInterval? = nil,
        previousPhase: String? = nil,
        previousPhaseDuration: TimeInterval? = nil
    ) {
        guard let session = session else { return }

        var message: [String: Any] = [
            "type": WatchMessageType.phaseChange.rawValue,
            "phase": phase,
            "cycleIndex": cycleIndex,
            "timestamp": Date().timeIntervalSince1970,
            "phaseChangeId": UUID().uuidString
        ]

        if let totalWorkTime { message["totalWorkTime"] = totalWorkTime }
        if let totalRestTime { message["totalRestTime"] = totalRestTime }
        if let elapsedTime { message["elapsedTime"] = elapsedTime }
        if let currentPhaseTime { message["currentPhaseTime"] = currentPhaseTime }
        if let previousPhase { message["previousPhase"] = previousPhase }
        if let previousPhaseDuration { message["previousPhaseDuration"] = previousPhaseDuration }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("iPhone: Failed to send phase change: \(error)")
            }
        }

        // Always persist latest phase info for reliability
        do {
            var context = session.applicationContext
            context.merge(message) { _, new in new }
            try session.updateApplicationContext(context)
        } catch {
            print("iPhone: Failed to persist phase change context: \(error)")
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
        print("iPhone: ✨✨✨ WCSession ACTIVATION COMPLETE ✨✨✨")
        print("iPhone: Activation state: \(activationState.rawValue) (0=notActivated, 1=inactive, 2=activated)")

        if let error = error {
            print("iPhone: ❌ Activation failed: \(error)")
            DispatchQueue.main.async {
                self.watchStatus = "接続エラー"
            }
            return
        }

        // デリゲートが自分自身に設定されているか確認
        if session.delegate === self {
            print("iPhone: ✅ Delegate is correctly set to WatchConnectivityService after activation")
        } else {
            print("iPhone: ❌ CRITICAL ERROR: Delegate is NOT set correctly!")
            print("iPhone: Current delegate: \(String(describing: session.delegate))")
            // デリゲートを再設定
            print("iPhone: 🔧 Re-setting delegate...")
            session.delegate = self
        }

        print("iPhone: 📱 Session info:")
        print("iPhone: - Is paired: \(session.isPaired)")
        print("iPhone: - Watch app installed: \(session.isWatchAppInstalled)")
        print("iPhone: - Is reachable: \(session.isReachable)")
        print("iPhone: - Has content pending: \(session.hasContentPending)")

        // 既存のapplicationContextをチェック（Watch側のワークアウト状態を復元）
        if !session.applicationContext.isEmpty {
            print("iPhone: 📦 Found existing applicationContext on activation:")
            print("iPhone: Context keys: \(session.applicationContext.keys.sorted())")

            // コマンドタイプのコンテキストを優先的に処理
            if session.applicationContext["type"] as? String == "command" {
                print("iPhone: 🎯 Found command in applicationContext!")
                if let command = session.applicationContext["lastCommand"] as? String {
                    print("iPhone: 🚀 Processing missed command: \(command)")
                }
            }
            processApplicationContext(session.applicationContext)
        } else {
            print("iPhone: 📭 No existing applicationContext on activation")
        }

        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
            self.watchStatus = session.isReachable ? "Watch接続済み" : "Watch待機中"

            // 接続可能になったらWatchに通知
            if session.isReachable {
                print("iPhone: 📡 Watch is reachable, sending heartbeat...")
                self.sendHeartbeatToWatch()
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
        print("iPhone: ⭐⭐⭐ didReceiveMessage CALLED ⭐⭐⭐")
        print("iPhone: 📥 Received message from Watch: \(message)")
        print("iPhone: Message keys: \(message.keys.sorted())")
        print("iPhone: Message type: \(message["type"] as? String ?? "unknown")")
        print("iPhone: Command: \(message["command"] as? String ?? "none")")
        print("iPhone: Source: \(message["source"] as? String ?? "unknown")")

        // デリゲートが正しく設定されているか確認
        if session.delegate === self {
            print("iPhone: ✅ Delegate is correctly set during message reception")
        } else {
            print("iPhone: ❌ WARNING: Delegate mismatch during message reception!")
        }

        // 重要: メッセージを確実に処理（同期的に処理）
        handleIncomingPayload(message)

        // Watch側に即座に確認応答を送信
        if session.isReachable {
            let reply: [String: Any] = [
                "status": "received",
                "timestamp": Date().timeIntervalSince1970,
                "processedType": message["type"] as? String ?? "unknown",
                "command": message["command"] as? String ?? "none"
            ]
            print("iPhone: 📤 Sending acknowledgment to Watch")
            session.sendMessage(reply, replyHandler: nil) { error in
                print("iPhone: ⚠️ Failed to send acknowledgment to Watch: \(error)")
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("iPhone: ⭐⭐⭐ didReceiveMessage WITH REPLY HANDLER CALLED ⭐⭐⭐")
        print("iPhone: 📥 Received message from Watch (with reply): \(message)")
        print("iPhone: Message keys: \(message.keys.sorted())")
        print("iPhone: Message type: \(message["type"] as? String ?? "unknown")")
        print("iPhone: Command: \(message["command"] as? String ?? "none")")
        print("iPhone: Source: \(message["source"] as? String ?? "unknown")")

        // pingメッセージへの応答
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["type": "pong", "timestamp": Date().timeIntervalSince1970])
            return
        }

        // メッセージを処理
        handleIncomingPayload(message)

        // Watch側に成功応答を返す
        let response: [String: Any] = [
            "received": true,
            "timestamp": Date().timeIntervalSince1970,
            "processedType": message["type"] as? String ?? "unknown",
            "processedCommand": message["command"] as? String ?? "none",
            "success": true
        ]
        print("iPhone: 📤 Sending reply to Watch: \(response)")
        replyHandler(response)
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
        
        // commandIdを記録
        if let commandId = context["commandId"] as? String {
            lastProcessedCommandId = commandId
        }

        if context["wakeUp"] as? Bool == true {
            print("iPhone: 🚨 Wake-up flag detected in applicationContext")
            DispatchQueue.main.async {
                self.watchStatus = "Watch起動要求"
            }
        }

        // 時間データを抽出
        let watchTotalWorkTime = context["totalWorkTime"] as? TimeInterval ?? 0
        let watchTotalRestTime = context["totalRestTime"] as? TimeInterval ?? 0
        let watchCurrentPhaseTime = context["currentPhaseTime"] as? TimeInterval
        _ = context["elapsedTime"] as? TimeInterval ?? 0  // 現在は使用していないが後で使う可能性があるため残す
        let watchCurrentPhase = context["currentPhase"] as? String ?? "idle"
        if let watchCycleIndex = context["cycleIndex"] as? Int {
            DispatchQueue.main.async {
                SessionManager.shared.cycleIndex = watchCycleIndex
            }
        }

        print("iPhone: ⏱️ Watch times - Work: \(watchTotalWorkTime)s, Rest: \(watchTotalRestTime)s, Phase: \(watchCurrentPhase)")

        // コマンドタイプのメッセージをチェック
        if let type = context["type"] as? String, type == "command",
           let command = context["lastCommand"] as? String {
            print("iPhone: 🎯 Found command in applicationContext: '\(command)'")

            // タイムスタンプをチェック（古すぎるコマンドは実行しない）
            var shouldExecute = true
            if let timestamp = context["commandTimestamp"] as? TimeInterval {
                let commandAge = Date().timeIntervalSince(Date(timeIntervalSince1970: timestamp))
                // タイムスタンプチェックを緩和：60分以内のコマンドを実行
                if commandAge < 3600 { // 60分以内のコマンドを実行
                    print("iPhone: ⏰ Command is recent enough (\(Int(commandAge))s old), executing...")
                    shouldExecute = true
                } else {
                    print("iPhone: ⚠️ Command is too old (\(Int(commandAge))s > 3600s), skipping")
                    shouldExecute = false
                }
            } else {
                // タイムスタンプがない場合も実行（後方互換性）
                print("iPhone: ⏰ No timestamp found, executing command anyway...")
                shouldExecute = true
            }

            if shouldExecute {
                DispatchQueue.main.async { [weak self] in
                    // コマンドを実行し、時間データも同期
                    self?.handleWatchCommandWithTimeSync(
                        command: command,
                        totalWorkTime: watchTotalWorkTime,
                        totalRestTime: watchTotalRestTime,
                        currentPhase: watchCurrentPhase,
                        currentPhaseTime: watchCurrentPhaseTime,
                        previousPhase: context["previousPhase"] as? String,
                        previousPhaseDuration: context["previousPhaseDuration"] as? TimeInterval
                    )
                    self?.lastMessageTime = Date()
                }
            }
        }

        // ワークアウト状態もチェック
        if let workoutState = context["workoutState"] as? String {
            print("iPhone: 🏃 Watch workout state: \(workoutState)")
            if workoutState == "running" || workoutState == "work" || workoutState == "rest" {
                // Watchでワークアウトが実行中の場合、iPhoneでも開始（時間データ付き）
                print("iPhone: 🚀 Auto-starting session based on Watch state with time sync")
                DispatchQueue.main.async {
                    if SessionManager.shared.currentPhase == .idle {
                        SessionManager.shared.startSessionWithTimeSync(
                            totalWorkTime: watchTotalWorkTime,
                            totalRestTime: watchTotalRestTime
                        )
                        SessionManager.shared.syncTimeFromWatch(
                            totalWorkTime: watchTotalWorkTime,
                            totalRestTime: watchTotalRestTime,
                            currentPhaseIdentifier: watchCurrentPhase,
                            currentPhaseTime: watchCurrentPhaseTime
                        )
                    } else {
                        // 既に動作中の場合は時間だけ同期
                        SessionManager.shared.syncTimeFromWatch(
                            totalWorkTime: watchTotalWorkTime,
                            totalRestTime: watchTotalRestTime,
                            currentPhaseIdentifier: watchCurrentPhase,
                            currentPhaseTime: watchCurrentPhaseTime
                        )
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
                case WatchMessageType.wakeUp.rawValue:
                    print("iPhone: ⏰ Received wakeUp request from Watch")
                    self.watchStatus = "Watch起動要求"

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
                    // Watchからのコマンド処理（時間データ付き）
                    print("iPhone: 📨 Received command message via direct sendMessage")
                    print("iPhone: 🔍 Source: \(payload["source"] as? String ?? "unknown")")
                    if let command = payload["command"] as? String {
                        print("iPhone: 🎯 Command string found: '\(command)'")

                        // 時間データも抽出
                        let watchTotalWorkTime = payload["totalWorkTime"] as? TimeInterval ?? 0
                        let watchTotalRestTime = payload["totalRestTime"] as? TimeInterval ?? 0
                        let watchCurrentPhase = payload["currentPhase"] as? String ?? "idle"
                        if let incomingCycleIndex = payload["cycleIndex"] as? Int {
                            SessionManager.shared.cycleIndex = incomingCycleIndex
                        }

                        print("iPhone: ⏱️ Message includes times - Work: \(watchTotalWorkTime)s, Rest: \(watchTotalRestTime)s")

                        let watchCurrentPhaseTime = payload["currentPhaseTime"] as? TimeInterval
                        let previousPhase = payload["previousPhase"] as? String
                        let previousPhaseDuration = payload["previousPhaseDuration"] as? TimeInterval

                        // 重要: 実際にコマンドを実行する
                        self.handleWatchCommandWithTimeSync(
                            command: command,
                            totalWorkTime: watchTotalWorkTime,
                            totalRestTime: watchTotalRestTime,
                            currentPhase: watchCurrentPhase,
                            currentPhaseTime: watchCurrentPhaseTime,
                            previousPhase: previousPhase,
                            previousPhaseDuration: previousPhaseDuration
                        )
                        self.watchStatus = "✅ \(command)"

                        // 成功フィードバックを送信
                        if session?.isReachable == true {
                            let ackMessage: [String: Any] = [
                                "type": "commandAck",
                                "command": command,
                                "success": true,
                                "timestamp": Date().timeIntervalSince1970
                            ]
                            print("iPhone: 📤 Sending command acknowledgment to Watch")
                            session?.sendMessage(ackMessage, replyHandler: nil) { error in
                                print("iPhone: ⚠️ Failed to send ack: \(error)")
                            }
                        }
                    } else {
                        print("iPhone: ⚠️ Received command message but no command string found")
                        print("iPhone: Payload keys: \(payload.keys)")
                    }

                default:
                    break
                }
            } else {
                // 従来の処理（後方互換性のため）+ 時間データ同期
                if let heartRate = payload["heartRate"] as? Double {
                    self.watchHeartRate = heartRate
                    self.heartRateSubject.send(heartRate)
                    self.watchStatus = "HR: \(Int(heartRate))"
                }

                if let elapsedTime = payload["elapsedTime"] as? TimeInterval {
                    self.watchElapsedTime = elapsedTime
                    self.watchElapsedTimeString = Self.formatTime(elapsedTime)
                }

                // 時間データが含まれている場合は同期
                if let watchTotalWorkTime = payload["totalWorkTime"] as? TimeInterval,
                   let watchTotalRestTime = payload["totalRestTime"] as? TimeInterval {
                    print("iPhone: 🔄 Syncing time data from Watch - Work: \(watchTotalWorkTime)s, Rest: \(watchTotalRestTime)s")
                    SessionManager.shared.syncTimeFromWatch(
                        totalWorkTime: watchTotalWorkTime,
                        totalRestTime: watchTotalRestTime,
                        currentPhaseIdentifier: payload["currentPhase"] as? String,
                        currentPhaseTime: payload["currentPhaseTime"] as? TimeInterval,
                        completedPhaseIdentifier: payload["previousPhase"] as? String,
                        completedPhaseDuration: payload["previousPhaseDuration"] as? TimeInterval
                    )
                }

                if let cycleIndex = payload["cycleIndex"] as? Int {
                    SessionManager.shared.cycleIndex = cycleIndex
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
        handleWatchCommandWithTimeSync(command: command, totalWorkTime: 0, totalRestTime: 0, currentPhase: "idle")
    }

    private func handleWatchCommandWithTimeSync(
        command: String,
        totalWorkTime: TimeInterval,
        totalRestTime: TimeInterval,
        currentPhase: String,
        currentPhaseTime: TimeInterval? = nil,
        previousPhase: String? = nil,
        previousPhaseDuration: TimeInterval? = nil
    ) {
        print("iPhone: 🔧 handleWatchCommandWithTimeSync called with: '\(command)'")
        print("iPhone: ⏱️ Time sync - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s, Phase: \(currentPhase)")
        if let currentPhaseTime {
            print("iPhone: ⏱️ Current phase elapsed: \(currentPhaseTime)s")
        }
        if let previousPhase {
            print("iPhone: ✅ Completed phase identifier: \(previousPhase), duration: \(previousPhaseDuration ?? -1)s")
        }

        // 必ずメインスレッドで実行
        DispatchQueue.main.async { [weak self] in
            guard self != nil else {
                print("iPhone: ⚠️ self is nil, cannot execute command")
                return
            }

            print("iPhone: 🎯 On main thread, current SessionManager phase: \(SessionManager.shared.currentPhase)")
            print("iPhone: 🚀 Executing command: '\(command)' on main thread with time sync")

            switch command {
            case "togglePhase":
                print("iPhone: 📱 Calling SessionManager.shared.togglePhase() with time sync")
                print("iPhone: 📊 Before toggle - Phase: \(SessionManager.shared.currentPhase)")
                // 時間データを同期してからフェーズ切り替え
                SessionManager.shared.syncTimeFromWatch(
                    totalWorkTime: totalWorkTime,
                    totalRestTime: totalRestTime,
                    currentPhaseIdentifier: currentPhase,
                    currentPhaseTime: currentPhaseTime,
                    completedPhaseIdentifier: previousPhase,
                    completedPhaseDuration: previousPhaseDuration
                )
                SessionManager.shared.togglePhase()
                print("iPhone: 📊 After toggle - Phase: \(SessionManager.shared.currentPhase)")
                print("iPhone: ✅ togglePhase() with time sync completed")

            case "startSession":
                print("iPhone: 📱 Calling SessionManager.shared.startSession() with time sync")
                print("iPhone: 📊 Current phase before start: \(SessionManager.shared.currentPhase)")
                // すでに開始している場合はスキップ
                if SessionManager.shared.currentPhase == .idle {
                    print("iPhone: 🆕 Session is idle, starting new session")
                    SessionManager.shared.startSessionWithTimeSync(
                        totalWorkTime: totalWorkTime,
                        totalRestTime: totalRestTime
                    )
                } else {
                    print("iPhone: ⚠️ Session already active (phase: \(SessionManager.shared.currentPhase)), syncing time only")
                }
                SessionManager.shared.syncTimeFromWatch(
                    totalWorkTime: totalWorkTime,
                    totalRestTime: totalRestTime,
                    currentPhaseIdentifier: currentPhase,
                    currentPhaseTime: currentPhaseTime
                )
                print("iPhone: 📊 Current phase after start: \(SessionManager.shared.currentPhase)")
                print("iPhone: ✅ startSession() with time sync completed")

            case "endSession":
                print("iPhone: 📱 Calling SessionManager.shared.endSession() with time sync")
                print("iPhone: 📊 Current phase before end: \(SessionManager.shared.currentPhase)")
                // 終了前に最終的な時間を同期
                SessionManager.shared.syncTimeFromWatch(
                    totalWorkTime: totalWorkTime,
                    totalRestTime: totalRestTime,
                    currentPhaseIdentifier: currentPhase,
                    currentPhaseTime: currentPhaseTime
                )
                SessionManager.shared.endSession()
                print("iPhone: 📊 Current phase after end: \(SessionManager.shared.currentPhase)")
                print("iPhone: ✅ endSession() with time sync completed")

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
            self?.watchStatus = "✅ \(command)"
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
