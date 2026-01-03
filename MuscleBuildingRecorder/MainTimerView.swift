import SwiftUI
import Combine
import UIKit

struct MainTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @EnvironmentObject var proUserManager: ProUserManager
    @ObservedObject private var watchConnectivity = WatchConnectivityService.shared
    @ObservedObject private var adManager = RewardedAdManager.shared
    @State private var showingInputSheet = false
    @State private var showingSummary = false
    @State private var showingExerciseSelection = false
    @State private var watchCheckResult: WatchCheckResult = .notChecked
    @State private var isShowingAd = false
    @State private var pulseAnimation = false
    @State private var exerciseSwipeOffset: CGFloat = 0

    enum WatchCheckResult {
        case notChecked, connected, unreachable, timeout
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 最上部: 大きな状態表示ヘッダー
                statusHeaderSection
                    .frame(height: geometry.size.height * 0.10)

                // 種目エリア（スワイプ対応）
                exerciseSection
                    .frame(height: geometry.size.height * 0.12)
                    .padding(.horizontal)

                // 中央: タイマーと目標表示
                timerAndTargetSection
                    .frame(height: geometry.size.height * 0.22)

                // 心拍数表示
                heartRateSection
                    .frame(height: geometry.size.height * 0.10)

                // メインアクションボタンエリア
                mainActionSection(geometry: geometry)
                    .frame(height: geometry.size.height * 0.32)

                // 下部: 完了ボタンと状態表示
                secondaryControlsSection
                    .frame(height: geometry.size.height * 0.14)
                    .padding(.horizontal)
            }
            .background(animatedBackground)
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
        .onReceive(watchConnectivity.$showExerciseSelectionRequested) { requested in
            // Watchから種目選択画面の表示リクエストを受信
            if requested {
                showingExerciseSelection = true
                // フラグをリセット
                watchConnectivity.showExerciseSelectionRequested = false
            }
        }
        .onAppear {
            // SessionManagerの変更を監視してWatchに送信
            setupSessionObservers()
            // パルスアニメーション開始
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    // MARK: - Status Header Section (大きな状態表示)
    private var statusHeaderSection: some View {
        HStack {
            // 状態アイコンとテキスト
            HStack(spacing: 12) {
                Text(phaseEmoji)
                    .font(.system(size: 32))
                    .scaleEffect(pulseAnimation && sessionManager.currentPhase != .idle ? 1.1 : 1.0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(phaseStatusText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if sessionManager.currentPhase != .idle {
                        Text("Cycle \(sessionManager.cycleIndex + 1)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Spacer()

            // 合計時間表示（見やすく改善）
            if sessionManager.currentPhase != .idle {
                HStack(spacing: 12) {
                    // 筋トレ総時間
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("筋トレ")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text(formatTime(sessionManager.totalWorkTime))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)

                    // 休憩総時間
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                            Text("休憩")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text(formatTime(sessionManager.totalRestTime))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.2))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.1))
    }

    // MARK: - Exercise Section (種目表示・スワイプ対応)
    private var exerciseSection: some View {
        VStack(spacing: 8) {
            if sessionManager.currentPhase != .idle {
                // 種目表示エリア（タップで変更可能）
                Button(action: { showingExerciseSelection = true }) {
                    HStack {
                        // 左矢印インジケーター
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))

                        Spacer()

                        // 種目情報
                        VStack(spacing: 4) {
                            Text(sessionManager.selectedCategory)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))

                            Text(sessionManager.selectedExercise)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // 右矢印インジケーター
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.width < -50 || value.translation.width > 50 {
                                showingExerciseSelection = true
                            }
                        }
                )
            } else {
                // 待機中
                VStack(spacing: 4) {
                    Text("筋トレ記録")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("スタートボタンを押して開始")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Phase Helpers
    private var phaseEmoji: String {
        switch sessionManager.currentPhase {
        case .idle: return "🏠"
        case .work: return "💪"
        case .rest: return "😮‍💨"
        }
    }

    private var phaseStatusText: String {
        switch sessionManager.currentPhase {
        case .idle: return "待機中"
        case .work: return "セット実行中"
        case .rest: return "休憩中"
        }
    }

    // MARK: - Timer and Target Section (タイマーと目標表示)
    private var timerAndTargetSection: some View {
        VStack(spacing: 12) {
            // 大きなタイマー表示
            Text(timerText)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .scaleEffect(pulseAnimation && sessionManager.currentPhase == .work ? 1.02 : 1.0)

            // 目標表示（回数 × 重量）
            if sessionManager.currentPhase != .idle {
                HStack(spacing: 8) {
                    Text("目標:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    Text("\(Int(sessionManager.currentReps))回")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)

                    Text("×")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    Text("\(String(format: "%.1f", sessionManager.currentLoad))kg")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)

                    // 入力ボタン（小）
                    Button(action: { showingInputSheet = true }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.2))
                .cornerRadius(20)
            }

            // 総経過時間（見やすく改善）
            if sessionManager.currentPhase != .idle {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("総時間")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatTime(sessionManager.elapsedTime))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Heart Rate Section (心拍数表示)
    private var heartRateSection: some View {
        HStack(spacing: 40) {
            // 心拍数
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(heartRateManager.currentHeartRate))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("bpm")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // 心拍数傾き
            HStack(spacing: 10) {
                Image(systemName: heartRateManager.heartRateSlope >= 0 ?
                      "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(heartRateManager.heartRateSlope >= 0 ? .orange : .cyan)

                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%+.1f", heartRateManager.heartRateSlope))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text("bpm/分")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // 接続ステータス
            VStack(spacing: 2) {
                Circle()
                    .fill(heartRateManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(heartRateManager.isConnected ? "接続中" : "未接続")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
        .padding(.horizontal)
    }

    // MARK: - Main Action Section (大きなアクションボタン)
    private func mainActionSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            if sessionManager.currentPhase == .idle {
                // 待機中: 大きなスタートボタン
                Button(action: startSessionWithWatchCheck) {
                    VStack(spacing: 16) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 70))
                        Text("スタート")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(width: geometry.size.width * 0.8,
                           height: geometry.size.width * 0.55)
                    .background(
                        RoundedRectangle(cornerRadius: 35)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .green.opacity(0.5), radius: 20, x: 0, y: 10)
                    )
                }
                .scaleEffect(pulseAnimation ? 1.02 : 1.0)

            } else if sessionManager.currentPhase == .work {
                // 運動中: 状態表示 + 休憩ボタン
                VStack(spacing: 12) {
                    // 現在の状態表示
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                        Text("筋トレ中")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(20)

                    // 休憩ボタン（大）
                    Button(action: { sessionManager.togglePhase() }) {
                        HStack(spacing: 16) {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 40))
                            Text("休憩に移行")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(width: geometry.size.width * 0.85,
                               height: geometry.size.width * 0.35)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .blue.opacity(0.5), radius: 15, x: 0, y: 8)
                        )
                    }
                }

            } else if sessionManager.currentPhase == .rest {
                // 休憩中: 状態表示 + 筋トレボタン + 保存ボタン
                VStack(spacing: 12) {
                    // 現在の状態表示
                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.title2)
                        Text("休憩中")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(20)

                    // 筋トレボタン（大）
                    Button(action: { sessionManager.togglePhase() }) {
                        HStack(spacing: 16) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 40))
                            Text("次のセットへ")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(width: geometry.size.width * 0.85,
                               height: geometry.size.width * 0.32)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.7)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: .red.opacity(0.5), radius: 15, x: 0, y: 8)
                        )
                    }

                    // サブボタン（保存・入力）
                    HStack(spacing: 12) {
                        Button(action: { sessionManager.saveCurrentCycle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("セット保存")
                            }
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(20)
                        }

                        Button(action: { showingInputSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.pencil")
                                Text("入力変更")
                            }
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(20)
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: sessionManager.currentPhase)
    }

    // MARK: - Secondary Controls Section
    private var secondaryControlsSection: some View {
        HStack(spacing: 20) {
            if sessionManager.currentPhase != .idle {
                // 完了ボタン
                Button(action: {
                    finishWorkoutWithAdGate()
                }) {
                    Label("完了", systemImage: "stop.circle.fill")
                        .font(.callout)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(12)
                }
                .disabled(isShowingAd)

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

    // アニメーション付き背景
    private var animatedBackground: some View {
        ZStack {
            // ベースグラデーション
            backgroundGradient
                .ignoresSafeArea()

            // パルスエフェクト（運動中のみ）
            if sessionManager.currentPhase == .work {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .scaleEffect(pulseAnimation ? 2.5 : 1.5)
                    .opacity(pulseAnimation ? 0 : 0.3)
                    .blur(radius: 50)
            }

            // 休憩中のウェーブエフェクト
            if sessionManager.currentPhase == .rest {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .scaleEffect(pulseAnimation ? 2.0 : 1.2)
                    .opacity(pulseAnimation ? 0 : 0.2)
                    .blur(radius: 40)
                    .offset(y: 100)
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch sessionManager.currentPhase {
            case .idle:
                return [Color(white: 0.12), Color(white: 0.05)]
            case .work:
                return [Color(red: 0.7, green: 0.15, blue: 0.15),
                        Color(red: 0.4, green: 0.08, blue: 0.08)]
            case .rest:
                return [Color(red: 0.1, green: 0.25, blue: 0.5),
                        Color(red: 0.05, green: 0.15, blue: 0.35)]
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
                    // HealthKit経由で心拍数が取得できる場合はポップアップ不要
                    // HeartRateManagerが自動でHealthKitにフォールバックするため
                    self.actuallyStartSession()
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
            guard phase == .idle else { return }
            watchConnectivity.sendPhaseChange(
                phase: phase.rawValue,
                cycleIndex: sessionManager.cycleIndex,
                totalWorkTime: sessionManager.totalWorkTime,
                totalRestTime: sessionManager.totalRestTime,
                elapsedTime: sessionManager.elapsedTime,
                currentPhaseTime: 0,
                previousPhase: nil,
                previousPhaseDuration: nil
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let time = Int(seconds)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let secs = time % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    // MARK: - Ad Gate for Workout Completion
    /// トレーニング完了時の広告ゲート処理
    /// 1. まずセッションを保存（広告表示中の中断でもデータを失わない）
    /// 2. Proユーザーなら即リザルト表示
    /// 3. 非Proユーザーは広告表示後にリザルト表示
    /// 4. 広告失敗時は即リザルト表示（フォールバック）
    private func finishWorkoutWithAdGate() {
        print("MainTimerView: finishWorkoutWithAdGate called")

        // 1. まずセッションを保存（データ保護）
        sessionManager.endSession()
        print("MainTimerView: Session ended and saved")

        // 2. Proユーザーは広告をスキップ
        if proUserManager.isPro {
            print("MainTimerView: Pro user detected, skipping ad")
            showingSummary = true
            return
        }

        // 3. 広告が準備できていない場合は即リザルト（フォールバック）
        print("MainTimerView: Ad state = \(adManager.state), isAdReady = \(adManager.isAdReady)")
        guard adManager.isAdReady else {
            print("MainTimerView: Ad not ready, showing summary directly (fallback)")
            showingSummary = true
            // 次回のために広告を読み込み
            adManager.preloadAd()
            return
        }

        // 4. 広告を表示
        print("MainTimerView: Showing rewarded ad...")
        isShowingAd = true
        showRewardedAd { success in
            DispatchQueue.main.async {
                print("MainTimerView: Ad completed with success=\(success)")
                self.isShowingAd = false
                // 広告の成否に関わらずリザルト画面へ
                self.showingSummary = true
            }
        }
    }

    /// リワード広告を表示
    private func showRewardedAd(completion: @escaping (Bool) -> Void) {
        // rootViewControllerを取得
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("MainTimerView: Could not find root view controller")
            completion(false)
            return
        }

        // 最前面のViewControllerを取得（モーダルが表示されている場合など）
        var topViewController = rootViewController
        while let presented = topViewController.presentedViewController {
            topViewController = presented
        }

        adManager.showAd(from: topViewController) { success in
            completion(success)
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
