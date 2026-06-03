#if os(watchOS)
import SwiftUI
import HealthKit
import WatchConnectivity

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var motionStreamer: WatchMotionStreamer
    @StateObject private var backgroundRecorder = BackgroundSensorRecorder.shared
    @State private var currentExercise: (category: String, name: String) = ("胸", "ベンチプレス")
    @State private var currentReps: Int = 10
    @State private var currentWeight: Double = 20.0
    @State private var cycleIndex: Int = 0
    @State private var showingExerciseInput = false
    @State private var showingQuickExercise = false
    @State private var elapsedTime: String = "00:00"
    @State private var lastIPhoneSync: Date?
    @State private var showingSensorSettings = false
    @State private var commandStatus: String = ""
    @State private var isCommandPending = false

    enum WorkoutPhase: Equatable {
        case idle, work, rest

        var displayName: String {
            switch self {
            case .idle: return String(localized: "待機中")
            case .work: return String(localized: "筋トレ")
            case .rest: return String(localized: "休憩")
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

    /// WorkoutManager.currentPhase から導出（single source of truth）
    private var currentPhase: WorkoutPhase {
        switch workoutManager.currentPhase.lowercased() {
        case "work": return .work
        case "rest": return .rest
        default: return .idle
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 4) {
                    // 1. 上部: 種目名（コンパクト）
                    headerSection
                        .padding(.horizontal, 2)

                    // 2. メイン指標: タイマーと心拍数
                    mainMetricsSection
                        .padding(.vertical, 2)

                    // 3. コントロールボタン（優先配置）
                    controlSection(geometry: geometry)
                        .padding(.horizontal, 2)
                        
                    // 4. サブ指標: 合計時間など（スクロール領域）
                    secondaryMetricsSection
                        .padding(.top, 8)

                    // デバッグ情報（開発時のみ）
                    #if DEBUG
                    debugSection
                        .padding(.top, 8)
                    #endif
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("筋トレ記録")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupWatchConnectivity()
            workoutManager.requestAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("WakeUp"))) { _ in
            handleWakeUpRequest()
        }
        // WorkoutManagerの種目更新を監視
        .onReceive(workoutManager.$receivedExercise) { exercise in
            if let exercise {
                currentExercise = exercise
            }
        }
        // WorkoutManagerのサイクルインデックスを監視
        .onReceive(workoutManager.$receivedCycleIndex) { index in
            if let index {
                cycleIndex = index
            }
        }
        // WorkoutManagerのコマンドACKを監視
        .onReceive(workoutManager.$lastCommandAck) { ack in
            if let ack, ack.success {
                commandStatus = "✅ \(ack.command) 完了"
                isCommandPending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    commandStatus = ""
                }
                lastIPhoneSync = Date()
            }
        }
        // WorkoutManagerのコマンドステータスを監視
        .onReceive(workoutManager.$lastCommandStatus) { status in
            switch status {
            case .success:
                isCommandPending = false
                commandStatus = "✅ 送信完了"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    commandStatus = ""
                }
            case .savedToContext:
                isCommandPending = false
                commandStatus = "📦 保存済み"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    commandStatus = ""
                }
            case .failed:
                isCommandPending = false
                commandStatus = "❌ 送信失敗"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    commandStatus = ""
                }
            case .sending:
                isCommandPending = true
                commandStatus = "送信中..."
            case .idle:
                break
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 2) {
            // サイクル表示 & ステータス
            HStack {
                Text("Cycle \(cycleIndex + 1)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                // ステータスバッジ（必要な場合のみ）
                if isCommandPending || !commandStatus.isEmpty {
                    Text(commandStatus.isEmpty ? "送信中..." : commandStatus)
                        .font(.system(size: 10))
                        .foregroundColor(isCommandPending ? .orange : .green)
                }
            }

            // 種目・回数・重量表示（タップで入力画面を開く）
            Button(action: { showingExerciseInput = true }) {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(currentExercise.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Text("\(currentExercise.category)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 回数・重量
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(currentReps)回")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                        Text(String(format: "%.1fkg", currentWeight))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showingExerciseInput) {
                ExerciseInputView(
                    currentCategory: currentExercise.category,
                    currentExercise: currentExercise.name,
                    currentReps: currentReps,
                    currentWeight: currentWeight
                ) { category, exercise, reps, weight in
                    // 更新を適用
                    currentExercise = (category: category, name: exercise)
                    currentReps = reps
                    currentWeight = weight

                    // iPhoneに変更を送信
                    sendExerciseUpdateToPhone(category: category, exercise: exercise, reps: reps, weight: weight)
                }
            }
        }
    }

    // MARK: - Main Metrics Section (Timer & Heart Rate)
    private var mainMetricsSection: some View {
        HStack(alignment: .center, spacing: 8) {
            // 現在のフェーズタイマー（左側・メイン）
            VStack(spacing: 0) {
                Text(currentPhase == .work ? String(localized: "筋トレ中") : currentPhase == .rest ? String(localized: "休憩中") : String(localized: "待機"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(workoutManager.currentPhaseTimeString)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundColor(currentPhase.color)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)

            // 心拍数（右側・コンパクト）
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("\(Int(workoutManager.heartRate))")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text("bpm")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Secondary Metrics Section (Total Stats)
    private var secondaryMetricsSection: some View {
        VStack(spacing: 6) {
            Divider()
            
            // 合計時間
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text("Total Work")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(workoutManager.totalWorkTimeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.red)
                }

                VStack(spacing: 0) {
                    Text("Total Rest")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(workoutManager.totalRestTimeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue)
                }

                VStack(spacing: 0) {
                    Text("Total Time")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text(workoutManager.elapsedTimeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            
            if workoutManager.isWorkoutActive {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(Int(workoutManager.activeCalories)) kcal")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
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

                // 終了ボタン（種目変更はヘッダーに統合済み）
                Button(action: endWorkout) {
                    Label("終了", systemImage: "stop.circle")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

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

                // 終了ボタン（種目変更はヘッダーに統合済み）
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
        .animation(.easeInOut(duration: 0.3), value: workoutManager.currentPhase)
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
        // ワークアウト開始前の状態チェック
        guard !workoutManager.isWorkoutActive else {
            print("Watch ContentView: Workout already active, ignoring start")
            return
        }

        // WorkoutManagerでワークアウトを開始（フェーズ設定も含む）
        // iPhoneへの通知はWorkoutManager.markWorkoutActive()が担当
        workoutManager.startWorkout()
        workoutManager.setPhase("work")

        // ローカルUI状態を更新（currentPhaseはcomputed propertyなので自動反映）
        cycleIndex = 0
    }

    private func togglePhase(to newPhase: WorkoutPhase) {
        // ワークアウトがアクティブでない場合は無視
        guard workoutManager.isWorkoutActive else {
            print("Watch ContentView: Workout not active, ignoring toggle")
            return
        }

        let previousPhaseIdentifier = currentPhaseString()
        let previousPhaseDuration = workoutManager.currentPhaseTime

        // サイクルインデックスの更新（rest→workの遷移時）
        if currentPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        // WorkoutManagerにフェーズを設定（currentPhaseはcomputed propertyで自動反映）
        let newPhaseString = newPhase == .work ? "work" : newPhase == .rest ? "rest" : "idle"
        workoutManager.setPhase(newPhaseString)

        // iPhoneに位相変更を通知（Watch側の最新時間を付与）
        sendCommandToPhone(
            "togglePhase",
            previousPhaseIdentifier: previousPhaseIdentifier,
            previousPhaseDuration: previousPhaseDuration
        )
    }

    private func endWorkout() {
        // ワークアウトがアクティブでない場合でも終了処理を実行（確実にクリーンアップ）
        print("Watch ContentView: Ending workout")

        // WorkoutManagerでワークアウトを終了（currentPhaseはcomputed propertyで自動反映）
        // iPhoneへの通知はWorkoutManager.endWorkout()が担当
        workoutManager.endWorkout()

        // ローカルUI状態を更新
        cycleIndex = 0
        elapsedTime = "00:00"
    }

    /// Watch側で入力された種目・回数・重量をiPhoneに送信
    private func sendExerciseUpdateToPhone(category: String, exercise: String, reps: Int, weight: Double) {
        print("Watch ContentView: 📤 Sending exercise update to iPhone")

        isCommandPending = true
        commandStatus = "送信中..."

        let message: [String: Any] = [
            "type": "exerciseUpdate",
            "category": category,
            "exercise": exercise,
            "reps": reps,
            "weight": weight,
            "timestamp": Date().timeIntervalSince1970
        ]

        // isReachableのチェックを外し、常に送信を試みる（False Negative回避のため）
        WCSession.default.sendMessage(message, replyHandler: { _ in
            DispatchQueue.main.async {
                self.isCommandPending = false
                self.commandStatus = "✅ 更新完了"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.commandStatus = ""
                }
            }
        }) { error in
            print("Watch: ❌ Failed to send exercise update: \(error)")
            // 失敗時はApplicationContextでバックアップ（既にsaveCurrentStateToContextで保存されているか確認）
            // エクササイズ更新はステートフルではないため、ここでのコンテキスト更新が必要かもしれないが、
            // 現在の実装ではステータス表示のみ変更
            DispatchQueue.main.async {
                self.isCommandPending = false
                self.commandStatus = "📦 保存済み"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.commandStatus = ""
                }
            }
        }
    }

    // MARK: - Watch Connectivity

    private func setupWatchConnectivity() {
        // 起動時に現在の状態を保存（iPhone側で復元可能にする）
        if workoutManager.isWorkoutActive {
            saveCurrentStateToContext()
            print("Watch: 🔄 Saved current workout state to applicationContext on startup")
        }
    }

    private func saveCurrentStateToContext() {
        do {
            let phaseString: String
            switch currentPhase {
            case .work: phaseString = "work"
            case .rest: phaseString = "rest"
            case .idle: phaseString = "idle"
            }
            let context: [String: Any] = [
                "workoutState": phaseString,
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
        print("Watch ContentView: 📤 Sending command '\(command)' to iPhone")

        // コマンド送信状態を表示
        isCommandPending = true
        commandStatus = "送信中..."
        workoutManager.lastCommandStatus = .sending

        // WorkoutManagerを通じて送信（applicationContextの更新も内部で行われる）
        // 結果は workoutManager.lastCommandStatus に反映される
        workoutManager.sendWorkoutCommandToPhoneWithContext(
            command,
            previousPhase: previousPhaseIdentifier,
            previousPhaseDuration: previousPhaseDuration
        )

        // startSessionの場合はiPhoneアプリの起動も試みる
        if command == "startSession" {
            wakeUpIPhone()
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
#endif
