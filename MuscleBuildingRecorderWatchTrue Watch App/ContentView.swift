#if os(watchOS)
import SwiftUI
import HealthKit
import WatchConnectivity

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @State private var currentPhase: WorkoutPhase = .idle
    @State private var currentExercise: (category: String, name: String) = ("胸", "ベンチプレス")
    @State private var cycleIndex: Int = 0
    @State private var showingExerciseList = false
    @State private var elapsedTime: String = "00:00"
    @State private var lastIPhoneSync: Date?

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
        }
    }

    // MARK: - Metrics Section
    private var metricsSection: some View {
        VStack(spacing: 6) {
            // タイマー
            Text(workoutManager.isWorkoutActive ? workoutManager.elapsedTimeString : elapsedTime)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(currentPhase.color)

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

            Button("Manual HR Trigger") {
                workoutManager.debugTriggerHeartRate()
            }
            .font(.caption2)
            .padding(4)
            .background(Color.orange.opacity(0.3))
            .cornerRadius(4)
        }
        .padding(6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(6)
    }
    #endif

    // MARK: - Actions

    private func startWorkout() {
        // iPhoneに開始を通知
        sendCommandToPhone("startSession")

        // ローカルでもワークアウトを開始
        workoutManager.startWorkout()
        currentPhase = .work
        cycleIndex = 0
    }

    private func togglePhase(to newPhase: WorkoutPhase) {
        // iPhoneに位相変更を通知
        sendCommandToPhone("togglePhase")

        // ローカルの位相を更新
        currentPhase = newPhase

        if newPhase == .work {
            cycleIndex += 1
            workoutManager.togglePause()  // Resume
        } else if newPhase == .rest {
            workoutManager.togglePause()  // Pause
        }
    }

    private func endWorkout() {
        // iPhoneに終了を通知
        sendCommandToPhone("endSession")

        // ローカルでワークアウトを終了
        workoutManager.endWorkout()
        currentPhase = .idle
        cycleIndex = 0
        elapsedTime = "00:00"
    }

    private func requestExerciseChange() {
        // iPhoneに種目変更画面の表示を要求
        sendCommandToPhone("showExerciseSelection")
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = WatchConnectivityDelegate.shared
            session.activate()

            // デリゲートからの通知を購読
            WatchConnectivityDelegate.shared.onMessageReceived = { message in
                self.handleMessageFromPhone(message)
            }
        }
    }

    private func sendCommandToPhone(_ command: String) {
        guard WCSession.default.isReachable else {
            print("Watch: iPhone is not reachable")
            return
        }

        let message: [String: Any] = [
            "type": "command",
            "command": command,
            "timestamp": Date().timeIntervalSince1970
        ]

        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("Watch: Failed to send command \(command): \(error)")
        }

        lastIPhoneSync = Date()
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
                    if let phase = message["phase"] as? String {
                        self.updatePhase(from: phase)
                    }
                    if let index = message["cycleIndex"] as? Int {
                        self.cycleIndex = index
                    }

                case "command":
                    // コマンド処理
                    if let command = message["command"] as? String {
                        self.handleCommand(command)
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
        case "start":
            if !workoutManager.isWorkoutActive {
                workoutManager.startWorkout()
                currentPhase = .work
            }
        case "stop":
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("WakeUp"), object: nil)
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

        // コマンドをチェック
        if let command = applicationContext["lastCommand"] as? String {
            onMessageReceived?(["type": "command", "command": command])
        }
    }
}
#endif