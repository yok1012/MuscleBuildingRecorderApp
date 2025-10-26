import SwiftUI
import Combine

struct MainTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @ObservedObject private var watchConnectivity = WatchConnectivityService.shared
    @State private var showingInputSheet = false
    @State private var showingSummary = false
    @State private var showingExerciseSelection = false
    @State private var showWatchWarning = false
    @State private var watchCheckResult: WatchCheckResult = .notChecked

    enum WatchCheckResult {
        case notChecked, connected, unreachable, timeout
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 上部エリア: 種目名とサイクル表示
                headerSection
                    .frame(height: geometry.size.height * 0.15)
                    .padding(.horizontal)

                // 中央上部: タイマーと心拍数表示
                metricsSection
                    .frame(height: geometry.size.height * 0.25)

                // 中央下部: メインアクションボタンエリア
                mainActionSection(geometry: geometry)
                    .frame(height: geometry.size.height * 0.45)

                // 下部: その他のコントロール
                secondaryControlsSection
                    .frame(height: geometry.size.height * 0.15)
                    .padding(.horizontal)
            }
            .background(backgroundGradient)
        }
        .sheet(isPresented: $showingInputSheet) {
            ExerciseInputSheet()
        }
        .sheet(isPresented: $showingExerciseSelection) {
            ExerciseSelectionSheet()
        }
        .fullScreenCover(isPresented: $showingSummary) {
            SessionSummaryView()
        }
        .alert("Apple Watchとの通信", isPresented: $showWatchWarning) {
            Button("続行") {
                actuallyStartSession()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Apple Watchと通信できませんでした。\nWatch側でも手動で開始してください。")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowExerciseSelection"))) { _ in
            // Watchから種目選択画面の表示リクエストを受信
            showingExerciseSelection = true
        }
        .onAppear {
            // SessionManagerの変更を監視してWatchに送信
            setupSessionObservers()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            // サイクル表示
            HStack {
                Text("Cycle \(sessionManager.cycleIndex + 1)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                if sessionManager.currentPhase != .idle {
                    Text(sessionManager.currentPhase.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                }
            }

            // 種目名表示（大きく）
            HStack {
                if sessionManager.currentPhase != .idle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionManager.selectedCategory)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        HStack {
                            Text(sessionManager.selectedExercise)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Image(systemName: "chevron.down.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.title3)
                        }
                    }
                    .onTapGesture {
                        showingExerciseSelection = true
                    }
                } else {
                    Text("筋トレ記録")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                Spacer()

                // 種目変更ボタン
                if sessionManager.currentPhase != .idle {
                    Button(action: { showingExerciseSelection = true }) {
                        Label("種目変更", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Metrics Section
    private var metricsSection: some View {
        VStack(spacing: 16) {
            // タイマー表示
            Text(timerText)
                .font(.system(size: 56, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .shadow(radius: 10)

            // 心拍数表示
            HStack(spacing: 30) {
                // 心拍数
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(heartRateManager.currentHeartRate))")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("bpm")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }

                // 心拍数傾き
                HStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title3)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: "%.1f", heartRateManager.heartRateSlope))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("bpm/分")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }
            }
            .foregroundColor(.white)

            // 接続ステータス
            HStack {
                Circle()
                    .fill(heartRateManager.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(heartRateManager.statusMessage)
                    .font(.caption2)
                    .opacity(0.7)
            }
            .foregroundColor(.white)
        }
    }

    // MARK: - Main Action Section
    private func mainActionSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 20) {
            if sessionManager.currentPhase == .idle {
                // 待機中: スタートボタンを大きく表示
                Button(action: startSessionWithWatchCheck) {
                    VStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 60))
                        Text("スタート")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(width: geometry.size.width * 0.7,
                           height: geometry.size.width * 0.6)
                    .background(
                        RoundedRectangle(cornerRadius: 30)
                            .fill(Color.green)
                            .shadow(radius: 15)
                    )
                }
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 0.2), value: sessionManager.currentPhase)

            } else if sessionManager.currentPhase == .work {
                // 運動中: 休憩ボタンを大きく、運動ボタンを小さく
                VStack(spacing: 15) {
                    // 休憩ボタン（大）
                    Button(action: { sessionManager.togglePhase() }) {
                        VStack(spacing: 12) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 50))
                            Text("休憩へ")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(width: geometry.size.width * 0.75,
                               height: geometry.size.width * 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.blue)
                                .shadow(radius: 15)
                        )
                    }

                    // 入力ボタン（小）
                    Button(action: { showingInputSheet = true }) {
                        Label("重量・回数入力", systemImage: "square.and.pencil")
                            .font(.callout)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(15)
                    }
                    .foregroundColor(.white)
                }

            } else if sessionManager.currentPhase == .rest {
                // 休憩中: 運動ボタンを大きく、休憩ボタンを小さく
                VStack(spacing: 15) {
                    // 運動ボタン（大）
                    Button(action: { sessionManager.togglePhase() }) {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 50))
                            Text("筋トレへ")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(width: geometry.size.width * 0.75,
                               height: geometry.size.width * 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.red)
                                .shadow(radius: 15)
                        )
                    }

                    // 休憩完了ボタン（小）
                    HStack(spacing: 15) {
                        Button(action: { sessionManager.saveCurrentCycle() }) {
                            Label("保存", systemImage: "checkmark.circle")
                                .font(.callout)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.8))
                                .cornerRadius(15)
                        }
                        .foregroundColor(.white)

                        Button(action: { showingInputSheet = true }) {
                            Label("入力", systemImage: "square.and.pencil")
                                .font(.callout)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(15)
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sessionManager.currentPhase)
    }

    // MARK: - Secondary Controls Section
    private var secondaryControlsSection: some View {
        HStack(spacing: 20) {
            if sessionManager.currentPhase != .idle {
                // 完了ボタン
                Button(action: {
                    sessionManager.endSession()
                    showingSummary = true
                }) {
                    Label("完了", systemImage: "stop.circle.fill")
                        .font(.callout)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(12)
                }

                // Watch状態表示
                if watchConnectivity.isWatchConnected {
                    HStack {
                        Image(systemName: "applewatch")
                            .font(.caption)
                        Text(watchConnectivity.watchStatus)
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helper Properties
    private var backgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch sessionManager.currentPhase {
            case .idle: return [Color(white: 0.15), Color(white: 0.05)]
            case .work: return [Color(red: 0.8, green: 0.2, blue: 0.2),
                                Color(red: 0.6, green: 0.1, blue: 0.1)]
            case .rest: return [Color(red: 0.1, green: 0.3, blue: 0.6),
                                Color(red: 0.05, green: 0.2, blue: 0.4)]
            }
        }()

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var timerText: String {
        if sessionManager.currentPhase == .idle {
            let state = watchConnectivity.watchWorkoutState
            if state == .running || state == .paused {
                return watchConnectivity.watchElapsedTimeString
            }
        }
        return sessionManager.elapsedTimeString
    }

    // MARK: - Watch Connection Methods
    private func startSessionWithWatchCheck() {
        // Watchとの接続を確認
        watchConnectivity.checkWatchAvailability { available in
            DispatchQueue.main.async {
                if available {
                    self.watchCheckResult = .connected
                    self.actuallyStartSession()
                } else {
                    self.watchCheckResult = .unreachable
                    self.showWatchWarning = true
                }
            }
        }
    }

    private func actuallyStartSession() {
        sessionManager.startSession()
        // Watchへの起動コマンドを送信
        watchConnectivity.wakeUpWatch()
    }

    private func setupSessionObservers() {
        // SessionManagerのフェーズ変更を監視してWatchに通知
        _ = sessionManager.$currentPhase.sink { phase in
            watchConnectivity.sendPhaseChange(
                phase: phase.rawValue,
                cycleIndex: sessionManager.cycleIndex
            )
        }

        // 種目変更を監視してWatchに通知
        _ = sessionManager.$selectedExercise.sink { _ in
            watchConnectivity.sendExerciseChange(
                category: sessionManager.selectedCategory,
                exercise: sessionManager.selectedExercise
            )
        }
    }
}

// MARK: - Exercise Selection Sheet
struct ExerciseSelectionSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: String = ""
    @State private var selectedExercise: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // カテゴリー選択
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sessionManager.getAvailableCategories(), id: \.self) { category in
                            Button(action: {
                                selectedCategory = category
                                selectedExercise = ""
                            }) {
                                Text(category)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == category ?
                                              Color.blue : Color.gray.opacity(0.3))
                                    .foregroundColor(selectedCategory == category ?
                                                   .white : .primary)
                                    .cornerRadius(15)
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                // エクササイズリスト
                List {
                    ForEach(sessionManager.getExercises(for: selectedCategory.isEmpty ?
                                                        sessionManager.selectedCategory :
                                                        selectedCategory), id: \.self) { exercise in
                        Button(action: {
                            selectExercise(category: selectedCategory.isEmpty ?
                                         sessionManager.selectedCategory :
                                         selectedCategory,
                                         exercise: exercise)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise)
                                        .font(.headline)
                                    Text("\(selectedCategory.isEmpty ? sessionManager.selectedCategory : selectedCategory)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if exercise == sessionManager.selectedExercise {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("種目選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            selectedCategory = sessionManager.selectedCategory
            selectedExercise = sessionManager.selectedExercise
        }
    }

    private func selectExercise(category: String, exercise: String) {
        sessionManager.selectedCategory = category
        sessionManager.selectedExercise = exercise
        sessionManager.loadDefaultExerciseValues()

        // 現在のSetRecordを更新
        if let record = sessionManager.currentSetRecord {
            record.category = category
            record.name = exercise
        }

        // Watchに種目変更を通知
        WatchConnectivityService.shared.sendExerciseChange(category: category, exercise: exercise)

        dismiss()
    }
}