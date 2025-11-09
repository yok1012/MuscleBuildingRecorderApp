#if os(watchOS)
import SwiftUI
import HealthKit
import WatchConnectivity

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var motionStreamer: WatchMotionStreamer
    @StateObject private var backgroundRecorder = BackgroundSensorRecorder.shared
    @State private var currentPhase: WorkoutPhase = .idle
    @State private var currentExercise: (category: String, name: String) = ("胸", "ベンチプレス")
    @State private var cycleIndex: Int = 0
    @State private var showingExerciseList = false
    @State private var elapsedTime: String = "00:00"
    @State private var lastIPhoneSync: Date?
    @State private var showingSensorSettings = false
    @State private var commandStatus: String = ""
    @State private var isCommandPending = false

    enum WorkoutPhase {
        case idle, work, rest

        var displayName: String {
            switch self {
            case .idle: return "待機中"
            case .work: return "筋トレ"
            case .rest: return "休憩"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .gray
            case .work: return .red
            case .rest: return .blue
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    // 上部: 種目名とサイクル表示
                    headerSection
                        .padding(.horizontal, 4)

                    // 中央: 心拍数とタイマー
                    metricsSection
                        .padding(.vertical, 4)

                    // 下部: コントロールボタン（動的サイズ）
                    controlSection(geometry: geometry)
                        .padding(.horizontal, 4)

                    // デバッグ情報（開発時のみ）
                    #if DEBUG
                    debugSection
                        .padding(.top, 8)
                    #endif
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("筋トレ記録")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupWatchConnectivity()
            workoutManager.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("PhaseChanged"))) { notification in
            if let phase = notification.object as? String {
                updatePhase(from: phase)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WakeUp"))) { _ in
            handleWakeUpRequest()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 4) {
            // サイクル表示
            HStack {
                Text("Cycle \(cycleIndex + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(currentPhase.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(currentPhase.color.opacity(0.3))
                    .cornerRadius(6)
            }

            // 種目表示（タップで変更）
            Button(action: { requestExerciseChange() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentExercise.category)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(currentExercise.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // コマンドステータス表示
            if isCommandPending || !commandStatus.isEmpty {
                HStack {
                    if isCommandPending {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    Text(commandStatus)
                        .font(.caption2)
                        .foregroundColor(isCommandPending ? .orange : .green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.2))
                .cornerRadius(4)
            }
        }
    }

    // MARK: - Metrics Section
    private var metricsSection: some View {
        VStack(spacing: 6) {
            // 現在のフェーズタイマー
            VStack(spacing: 2) {
                Text(currentPhase == .work ? "筋トレ" : currentPhase == .rest ? "休憩" : "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(workoutManager.currentPhaseTimeString)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundColor(currentPhase.color)
            }

            // 合計時間
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("合計筋トレ")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(workoutManager.totalWorkTimeString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.red)
                }

                VStack(spacing: 2) {
                    Text("合計休憩")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(workoutManager.totalRestTimeString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue)
                }

                VStack(spacing: 2) {
                    Text("総時間")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(workoutManager.elapsedTimeString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            // 心拍数
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                    Text("\(Int(workoutManager.heartRate))")
                        .font(.system(size: 20, weight: .semibold))
                    Text("bpm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if workoutManager.isWorkoutActive {
                    Divider()
                        .frame(height: 20)

                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(Int(workoutManager.activeCalories))")
                            .font(.system(size: 14))
                        Text("kcal")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Control Section
    private func controlSection(geometry: GeometryProxy) -> some View {
        let screenWidth = geometry.size.width

        return VStack(spacing: 8) {
            if currentPhase == .idle {
                // 待機中: スタートボタンを大きく
                Button(action: startWorkout) {
                    VStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                        Text("スタート")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(width: screenWidth * 0.85, height: screenWidth * 0.5)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

            } else if currentPhase == .work {
                // 運動中: 休憩ボタンを大きく
                Button(action: { togglePhase(to: .rest) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 28))
                        Text("休憩へ")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: screenWidth * 0.85, height: screenWidth * 0.4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                // 小さい補助ボタン
                HStack(spacing: 8) {
                    Button(action: { requestExerciseChange() }) {
                        Label("種目", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: endWorkout) {
                        Label("終了", systemImage: "stop.circle")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            } else if currentPhase == .rest {
                // 休憩中: 運動ボタンを大きく
                Button(action: { togglePhase(to: .work) }) {
                    VStack(spacing: 4) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 28))
                        Text("筋トレへ")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: screenWidth * 0.85, height: screenWidth * 0.4)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())

                // 小さい補助ボタン
                HStack(spacing: 8) {
                    Button(action: { requestExerciseChange() }) {
                        Label("種目", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: endWorkout) {
                        Label("終了", systemImage: "stop.circle")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.3))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPhase)
    }

    // MARK: - Debug Section
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Debug Info")
                .font(.caption2)
                .foregroundColor(.yellow)
            Text("WM: \(workoutManager.debugMessage)")
                .font(.system(size: 9))
                .foregroundColor(.green)
            Text("Session: \(workoutManager.sessionState)")
                .font(.system(size: 9))
                .foregroundColor(.purple)
            Text("Query: \(workoutManager.queryStatus)")
                .font(.system(size: 9))
                .foregroundColor(.pink)
            if let syncTime = lastIPhoneSync {
                Text("Sync: \(Int(Date().timeIntervalSince(syncTime)))s ago")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
            }

            // Motion Streamer info
            HStack(spacing: 4) {
                Circle()
                    .fill(motionStreamer.isRunning ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text("Motion: \(motionStreamer.isRunning ? "\(motionStreamer.currentRateHz)Hz" : "Off")")
                    .font(.system(size: 9))
                    .foregroundColor(motionStreamer.isRunning ? .green : .red)
            }

            if motionStreamer.isRunning {
                Text("Samples: \(motionStreamer.totalSamples)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                if motionStreamer.pendingFileCount > 0 {
                    Text("Pending: \(motionStreamer.pendingFileCount) files")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }

            // Background Recording info
            HStack(spacing: 4) {
                Circle()
                    .fill(backgroundRecorder.isRecording ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text("BG Rec: \(backgroundRecorder.sessionState)")
                    .font(.system(size: 9))
                    .foregroundColor(backgroundRecorder.isRecording ? .green : .gray)
            }

            if backgroundRecorder.isRecording {
                Text("Duration: \(Int(backgroundRecorder.recordingDuration))s")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 4) {
                Button("Manual HR") {
                    workoutManager.debugTriggerHeartRate()
                }
                .font(.system(size: 8))
                .padding(2)
                .background(Color.orange.opacity(0.3))
                .cornerRadius(4)

                if backgroundRecorder.isRecording {
                    Button("Stop BG") {
                        backgroundRecorder.stopBackgroundRecording()
                    }
                    .font(.system(size: 8))
                    .padding(2)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(4)
                } else {
                    Button("Start BG") {
                        backgroundRecorder.startBackgroundRecording(
                            rateHz: 50,
                            sensors: [.accelerometer, .gyroscope, .deviceMotion]
                        )
                    }
                    .font(.system(size: 8))
                    .padding(2)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(4)
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
    }
    #endif

    // MARK: - Actions

    private func startWorkout() {
        // ローカルでもワークアウトを開始
        workoutManager.startWorkout()
        currentPhase = .work
        workoutManager.setPhase("work")
        cycleIndex = 0
        // タイマーは WorkoutManager.startWorkout() 内で開始されるため、ここでは何もしない

        // iPhoneに開始を通知
        sendCommandToPhone("startSession")
    }

    private func togglePhase(to newPhase: WorkoutPhase) {
        let previousPhaseIdentifier = currentPhaseString()
        let previousPhaseDuration = workoutManager.currentPhaseTime

        // ローカルの位相を更新
        currentPhase = newPhase

        // WorkoutManagerにフェーズを設定
        workoutManager.setPhase(newPhase == .work ? "work" : newPhase == .rest ? "rest" : "idle")

        // サイクルインデックスの更新（rest→workの遷移時）
        if currentPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        // 注意: pause/resumeは削除。フェーズ変更時にタイマーは継続して動作させる

        // iPhoneに位相変更を通知（Watch側の最新時間を付与）
        sendCommandToPhone(
            "togglePhase",
            previousPhaseIdentifier: previousPhaseIdentifier,
            previousPhaseDuration: previousPhaseDuration
        )
    }

    private func endWorkout() {
        // ローカルでワークアウトを終了
        workoutManager.endWorkout()
        currentPhase = .idle
        cycleIndex = 0
        elapsedTime = "00:00"

        // iPhoneに終了を通知
        sendCommandToPhone("endSession")
    }

    private func requestExerciseChange() {
        // iPhoneに種目変更画面の表示を要求
        sendCommandToPhone("showExerciseSelection")
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            // ContentView用のdelegateを設定（iPhone→Watchのメッセージを受信）
            let delegate = WatchConnectivityDelegate.shared
            delegate.onMessageReceived = { message in
                self.handleMessageFromPhone(message)
            }

            // 起動時に現在の状態を保存（iPhone側で復元可能にする）
            if workoutManager.isWorkoutActive {
                saveCurrentStateToContext()
                print("Watch: 🔄 Saved current workout state to applicationContext on startup")
            }
        }
    }

    private func saveCurrentStateToContext() {
        do {
            let context: [String: Any] = [
                "workoutState": currentPhase == .work ? "work" : currentPhase == .rest ? "rest" : "idle",
                "isActive": workoutManager.isWorkoutActive,
                "cycleIndex": cycleIndex,
                "timestamp": Date().timeIntervalSince1970
            ]
            try WCSession.default.updateApplicationContext(context)
            print("Watch: 💾 Current state saved to applicationContext")
        } catch {
            print("Watch: ❌ Failed to save state to applicationContext: \(error)")
        }
    }

    private func sendCommandToPhone(
        _ command: String,
        previousPhaseIdentifier: String? = nil,
        previousPhaseDuration: TimeInterval? = nil
    ) {
        // 先にapplicationContextを更新
        updateApplicationContextWithCommand(
            command,
            phaseIdentifier: currentPhaseString(),
            previousPhaseIdentifier: previousPhaseIdentifier,
            previousPhaseDuration: previousPhaseDuration
        )

        // コマンド送信状態を表示
        isCommandPending = true
        commandStatus = "送信中..."

        // WorkoutManagerを通じて送信（WorkoutManagerがWCSessionのdelegateを管理）
        workoutManager.sendWorkoutCommandToPhone(command)

        // startSessionの場合はiPhoneアプリの起動も試みる
        if command == "startSession" {
            wakeUpIPhone()
        }

        // 状態更新（WorkoutManagerから成功/失敗のコールバックがないため、短時間後に完了とみなす）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isCommandPending = false
            if WCSession.default.isReachable {
                self.commandStatus = "✅ 送信完了"
            } else {
                self.commandStatus = "📦 保存済み"
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.commandStatus = ""
            }
        }

        lastIPhoneSync = Date()
    }

    private func wakeUpIPhone() {
        print("Watch: 📱 Attempting to wake up iPhone app...")

        // HKHealthStoreを使ったバックグラウンド起動
        #if os(watchOS)
        if WCSession.default.isCompanionAppInstalled {
            // 高優先度メッセージを送信してiPhoneを起動
            let wakeMessage: [String: Any] = [
                "type": "wakeUp",
                "timestamp": Date().timeIntervalSince1970,
                "urgent": true
            ]

            WCSession.default.sendMessage(wakeMessage, replyHandler: { response in
                print("Watch: ✅ iPhone app woke up successfully")
            }) { error in
                print("Watch: ⚠️ Could not wake iPhone app: \(error)")
            }
        }
        #endif
    }

    private func updateApplicationContextWithCommand(
        _ command: String,
        phaseIdentifier: String,
        previousPhaseIdentifier: String?,
        previousPhaseDuration: TimeInterval?
    ) {
        do {
            // 新しいディクショナリを作成（applicationContextは読み取り専用）
            var context: [String: Any] = [
                "type": "command",
                "lastCommand": command,
                "commandTimestamp": Date().timeIntervalSince1970,
                // ユニークIDを追加して、同じコマンドでも更新がトリガーされるようにする
                "commandId": UUID().uuidString,
                "totalWorkTime": workoutManager.totalWorkTime,
                "totalRestTime": workoutManager.totalRestTime,
                "currentPhaseTime": workoutManager.currentPhaseTime,
                "elapsedTime": workoutManager.elapsedTime,
                "currentPhase": phaseIdentifier,
                "cycleIndex": cycleIndex
            ]
            if let previousPhaseIdentifier {
                context["previousPhase"] = previousPhaseIdentifier
                context["previousPhaseDuration"] = previousPhaseDuration ?? workoutManager.currentPhaseTime
            }
            try WCSession.default.updateApplicationContext(context)
            print("Watch: ✅ Command saved to applicationContext: \(command)")
            print("Watch: Context content: \(context)")
        } catch {
            print("Watch: ❌ Failed to update applicationContext with command '\(command)': \(error)")
        }
    }

    private func handleMessageFromPhone(_ message: [String: Any]) {
        DispatchQueue.main.async {
            if let type = message["type"] as? String {
                switch type {
                case "wakeUp":
                    // iPhoneからの起動要求
                    if !self.workoutManager.isWorkoutActive {
                        self.workoutManager.startWorkout()
                        self.currentPhase = .work
                    }

                case "exerciseChange":
                    // 種目変更通知
                    if let category = message["category"] as? String,
                       let exercise = message["exercise"] as? String {
                        self.currentExercise = (category: category, name: exercise)
                    }

                case "phaseChange":
                    // 位相変更通知
                    let phaseString = (message["phase"] as? String) ?? (message["currentPhase"] as? String)
                    let totalWork = message["totalWorkTime"] as? TimeInterval
                    let totalRest = message["totalRestTime"] as? TimeInterval
                    let elapsed = message["elapsedTime"] as? TimeInterval
                    let currentPhaseTime = message["currentPhaseTime"] as? TimeInterval
                    let previousPhase = message["previousPhase"] as? String
                    let previousDuration = message["previousPhaseDuration"] as? TimeInterval

                    if let phaseString {
                        self.workoutManager.applyPhaseChangeFromPhone(
                            phase: phaseString,
                            totalWorkTime: totalWork,
                            totalRestTime: totalRest,
                            elapsedTime: elapsed,
                            currentPhaseTime: currentPhaseTime,
                            previousPhase: previousPhase,
                            previousPhaseDuration: previousDuration
                        )
                        self.updatePhase(from: phaseString)
                    }

                    if let index = message["cycleIndex"] as? Int {
                        self.cycleIndex = index
                    }

                case "command":
                    // コマンド処理
                    if let command = message["command"] as? String {
                        self.handleCommand(command)
                    }
                    
                case "commandAck":
                    // iPhoneからのコマンド確認応答
                    if let command = message["command"] as? String,
                       let success = message["success"] as? Bool {
                        if success {
                            self.commandStatus = "✅ \(command) 完了"
                            self.isCommandPending = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                self.commandStatus = ""
                            }
                        }
                    }

                default:
                    break
                }
            }

            self.lastIPhoneSync = Date()
        }
    }

    private func handleCommand(_ command: String) {
        switch command {
        case "start", "startSession":
            if !workoutManager.isWorkoutActive {
                workoutManager.startWorkout()
                currentPhase = .work
            }
        case "stop", "endSession":
            workoutManager.endWorkout()
            currentPhase = .idle
        case "pause":
            if !workoutManager.isPaused {
                workoutManager.togglePause()
                currentPhase = .rest
            }
        case "resume":
            if workoutManager.isPaused {
                workoutManager.togglePause()
                currentPhase = .work
            }
        case "togglePhase":
            if currentPhase == .work {
                workoutManager.applyPhaseChangeFromPhone(
                    phase: "rest",
                    totalWorkTime: nil,
                    totalRestTime: nil,
                    elapsedTime: nil,
                    currentPhaseTime: 0,
                    previousPhase: "work",
                    previousPhaseDuration: nil
                )
                currentPhase = .rest
            } else if currentPhase == .rest {
                workoutManager.applyPhaseChangeFromPhone(
                    phase: "work",
                    totalWorkTime: nil,
                    totalRestTime: nil,
                    elapsedTime: nil,
                    currentPhaseTime: 0,
                    previousPhase: "rest",
                    previousPhaseDuration: nil
                )
                currentPhase = .work
            } else {
                workoutManager.startWorkout()
                currentPhase = .work
            }
        default:
            break
        }
    }

    private func updatePhase(from phaseString: String) {
        switch phaseString.lowercased() {
        case "work", "筋トレ":
            currentPhase = .work
        case "rest", "休憩":
            currentPhase = .rest
        case "idle", "待機中":
            currentPhase = .idle
        default:
            break
        }
    }

    private func currentPhaseString() -> String {
        switch currentPhase {
        case .work: return "work"
        case .rest: return "rest"
        case .idle: return "idle"
        }
    }

    private func handleWakeUpRequest() {
        if workoutManager.isWorkoutActive {
            // 既に稼働中の場合は現在の状態をiPhone側に確実に同期
            sendCommandToPhone("startSession")
        } else {
            startWorkout()
        }
    }
}

// MARK: - WatchConnectivity Delegate
class WatchConnectivityDelegate: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityDelegate()
    var onMessageReceived: (([String: Any]) -> Void)?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Watch: WCSession activation failed: \(error)")
        } else {
            print("Watch: WCSession activated")

            // 既存のアプリケーションコンテキストを確認
            let context = session.applicationContext
            if let category = context["currentCategory"] as? String,
               let exercise = context["currentExercise"] as? String {
                DispatchQueue.main.async {
                    // 種目情報を更新
                    NotificationCenter.default.post(
                        name: .init("UpdateExercise"),
                        object: ["category": category, "exercise": exercise]
                    )
                }
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Watch: Received message from iPhone: \(message)")
        onMessageReceived?(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("Watch: Received message with reply handler")

        // pingへの応答
        if let type = message["type"] as? String, type == "ping" {
            replyHandler(["type": "pong", "timestamp": Date().timeIntervalSince1970])
            return
        }

        onMessageReceived?(message)
        replyHandler(["received": true])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("Watch: Received application context: \(applicationContext)")

        // wakeUpフラグをチェック
        if applicationContext["wakeUp"] as? Bool == true {
            let wakePayload: [String: Any] = [
                "type": "wakeUp",
                "timestamp": Date().timeIntervalSince1970
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("WakeUp"), object: nil)
                self.onMessageReceived?(wakePayload)
            }
        }

        // 種目情報をチェック
        if let category = applicationContext["currentCategory"] as? String,
           let exercise = applicationContext["currentExercise"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .init("UpdateExercise"),
                    object: ["category": category, "exercise": exercise]
                )
            }
        }

        // コマンドやフェーズ更新を反映
        if applicationContext["type"] != nil {
            DispatchQueue.main.async { [weak self] in
                self?.onMessageReceived?(applicationContext)
            }
        } else if let command = applicationContext["lastCommand"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onMessageReceived?(["type": "command", "command": command])
            }
        }
    }
}
#endif
