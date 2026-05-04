import SwiftUI
import Combine
import UIKit
import UserNotifications
import CoreData

struct MainTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @EnvironmentObject var proUserManager: ProUserManager
    @ObservedObject private var watchConnectivity = WatchConnectivityService.shared
    @ObservedObject private var adManager = RewardedAdManager.shared
    @ObservedObject private var noteLogger = WorkoutNoteLogger.shared
    @ObservedObject private var buttonLayout = ButtonLayoutManager.shared
    @ObservedObject private var presetRunner = PresetRunner.shared
    @State private var showingInputSheet = false
    @State private var showingSummary = false
    @State private var showingExerciseSelection = false
    @State private var watchCheckResult: WatchCheckResult = .notChecked
    @State private var isShowingAd = false
    @State private var pulseAnimation = false
    @State private var exerciseSwipeOffset: CGFloat = 0
    @State private var showingFinishConfirmation = false
    @State private var showingRestSettings = false
    @State private var showingNoteSheet = false
    @State private var showingPresetPicker = false

    // インライン編集モード
    enum InlineEditMode: Equatable {
        case none
        case reps
        case load
    }
    @State private var inlineEditMode: InlineEditMode = .none

    enum WatchCheckResult {
        case notChecked, connected, unreachable, timeout
    }

    // iPad対応: ボタン等の最大幅を制限
    private let maxContentWidth: CGFloat = 500

    private func effectiveWidth(_ geometryWidth: CGFloat) -> CGFloat {
        min(geometryWidth, maxContentWidth)
    }

    /// 現在有効なメイン切替ボタンの縦位置（無料は強制中央）
    private var effectiveButtonPosition: MainButtonVerticalPosition {
        proUserManager.isPro ? buttonLayout.config.mainButtonVerticalPosition : .middle
    }

    var body: some View {
        GeometryReader { geometry in
            let position = effectiveButtonPosition
            VStack(spacing: 0) {
                // 上部配置: アクションボタンを画面の最上部へ
                if position == .top {
                    mainActionSection(geometry: geometry)
                        .frame(height: geometry.size.height * 0.32)
                }

                // 最上部: 大きな状態表示ヘッダー
                statusHeaderSection
                    .frame(height: geometry.size.height * 0.10)

                // 種目エリア（スワイプ対応）
                exerciseSection
                    .frame(height: geometry.size.height * 0.12)
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal)

                // 中央: タイマーと目標表示
                timerAndTargetSection
                    .frame(height: geometry.size.height * 0.22)

                // 心拍数表示
                heartRateSection
                    .frame(height: geometry.size.height * 0.10)
                    .frame(maxWidth: maxContentWidth)

                // 中央配置: アクションボタンを既定位置（心拍数の下）に
                if position == .middle {
                    mainActionSection(geometry: geometry)
                        .frame(height: geometry.size.height * 0.32)
                }

                // 緊急解除バー（スクリーンタイム制限適用中のみ表示）
                screenTimeUnlockBar
                    .frame(maxWidth: maxContentWidth)

                // 下部: 完了ボタンと状態表示
                secondaryControlsSection
                    .frame(height: geometry.size.height * 0.14)
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal)

                // 下部配置: アクションボタンを画面の最下部（secondaryControls の下）へ
                if position == .bottom {
                    mainActionSection(geometry: geometry)
                        .frame(height: geometry.size.height * 0.32)
                }
            }
            .frame(maxWidth: .infinity)
            .background(animatedBackground)
            .animation(.easeInOut(duration: 0.25), value: position)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if presetRunner.isRunning {
                presetProgressBanner
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingInputSheet) {
            ExerciseInputSheet()
                .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showingExerciseSelection) {
            ExerciseSelectionSheet()
                .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showingRestSettings) {
            RestTimeSettingsSheet()
                .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showingNoteSheet) {
            WorkoutNoteSheet()
                .environmentObject(sessionManager)
        }
        .sheet(isPresented: $showingPresetPicker) {
            PresetQuickPickerView()
        }
        .fullScreenCover(isPresented: $showingSummary) {
            SessionSummaryView()
                .environmentObject(sessionManager)
                .environmentObject(proUserManager)
        }
        .alert("トレーニング終了", isPresented: $showingFinishConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("終了する", role: .destructive) {
                finishWorkoutWithAdGate()
            }
        } message: {
            Text("トレーニングを終了しますか？\n\n総時間: \(formatTime(sessionManager.elapsedTime))\n筋トレ: \(formatTime(sessionManager.totalWorkTime))\n休憩: \(formatTime(sessionManager.totalRestTime))")
        }
        .onReceive(watchConnectivity.$showExerciseSelectionRequested) { requested in
            // Watchから種目選択画面の表示リクエストを受信
            if requested {
                showingExerciseSelection = true
                // フラグをリセット
                watchConnectivity.showExerciseSelectionRequested = false
            }
        }
        .onChange(of: sessionManager.sessionEndedFromWatch) { ended in
            if ended {
                sessionManager.sessionEndedFromWatch = false
                handleSessionEndedFromWatch()
            }
        }
        .onAppear {
            // SessionManagerの変更を監視してWatchに送信
            setupSessionObservers()
            // パルスアニメーション開始
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            // 通知のパーミッションをリクエスト
            requestNotificationPermission()
        }
    }

    // MARK: - Notification Permission
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            print("Notification permission granted: \(granted)")
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

            // 目標表示（回数 × 重量）- タップで直接編集可能
            if sessionManager.currentPhase != .idle {
                VStack(spacing: 8) {
                    // メイン表示行
                    HStack(spacing: 8) {
                        Text("目標:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        // 回数（タップで編集モード切替）
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inlineEditMode = inlineEditMode == .reps ? .none : .reps
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Text("\(Int(sessionManager.currentReps))回")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(inlineEditMode == .reps ? .white : .yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(inlineEditMode == .reps ? Color.yellow : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Text("×")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        // 重量（タップで編集モード切替）
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                inlineEditMode = inlineEditMode == .load ? .none : .load
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Text("\(String(format: "%.1f", sessionManager.currentLoad))kg")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(inlineEditMode == .load ? .white : .yellow)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(inlineEditMode == .load ? Color.yellow : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        // 詳細入力ボタン
                        Button(action: { showingInputSheet = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(20)

                    // インライン編集コントロール（展開時のみ表示）
                    if inlineEditMode != .none {
                        inlineEditControls
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                    }
                }
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

    // MARK: - Inline Edit Controls (インライン編集コントロール)
    private var inlineEditControls: some View {
        HStack(spacing: 12) {
            if inlineEditMode == .reps {
                // 回数編集
                inlineIncrementButton(value: -5, label: "-5", color: .red)
                inlineIncrementButton(value: -1, label: "-1", color: .orange)

                Text("\(Int(sessionManager.currentReps))")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(minWidth: 50)

                inlineIncrementButton(value: +1, label: "+1", color: .green.opacity(0.7))
                inlineIncrementButton(value: +5, label: "+5", color: .green)
            } else if inlineEditMode == .load {
                // 重量編集
                inlineIncrementButton(value: -5, label: "-5", color: .red)
                inlineIncrementButton(value: -1, label: "-1", color: .orange)

                Text(String(format: "%.1f", sessionManager.currentLoad))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(minWidth: 60)

                inlineIncrementButton(value: +1, label: "+1", color: .green.opacity(0.7))
                inlineIncrementButton(value: +5, label: "+5", color: .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
    }

    private func inlineIncrementButton(value: Double, label: String, color: Color) -> some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            withAnimation(.easeInOut(duration: 0.1)) {
                if inlineEditMode == .reps {
                    sessionManager.currentReps = max(1, sessionManager.currentReps + value)
                } else if inlineEditMode == .load {
                    sessionManager.currentLoad = max(0, sessionManager.currentLoad + value)
                }
            }
        }) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 54, height: 44)
                .background(color)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Heart Rate Section (心拍数表示)

    // 現在の心拍ゾーンを計算
    private var currentHeartRateZone: HeartRateZone {
        WidgetStateStore.shared.currentHeartRateZone(heartRate: heartRateManager.currentHeartRate)
    }

    private var heartRateSection: some View {
        HStack(spacing: 20) {
            // 心拍ゾーン表示（左端に追加）
            VStack(spacing: 4) {
                Circle()
                    .fill(currentHeartRateZone.color)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text("\(currentHeartRateZone.rawValue)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: currentHeartRateZone.color.opacity(0.6), radius: 4)
                Text(currentHeartRateZone.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.7))
            }

            // 心拍数
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(currentHeartRateZone.color)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            // 心拍数による自動フェーズ提案
            if let suggestedPhase = sessionManager.suggestedPhase {
                phaseSuggestionView(suggested: suggestedPhase)
                    .offset(y: 50)
            }
        }
    }

    // MARK: - Phase Suggestion View (心拍数自動判別の提案)
    @ViewBuilder
    private func phaseSuggestionView(suggested: WorkoutPhase) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.title3)
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("心拍数から判断")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                Text("\(suggested == .work ? "筋トレ" : "休憩")に切り替えますか？")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }

            Spacer()

            Button(action: {
                sessionManager.acceptPhaseSuggestion()
            }) {
                Text("切替")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow)
                    .cornerRadius(8)
            }

            Button(action: {
                sessionManager.dismissPhaseSuggestion()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding(.horizontal, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sessionManager.suggestedPhase != nil)
    }

    // MARK: - Preset Progress Banner（プリセット実行中に上部に表示）
    @ViewBuilder
    private var presetProgressBanner: some View {
        if let preset = presetRunner.activePreset, let step = presetRunner.currentStep {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let phaseRemaining = presetRunner.secondsUntilPhaseChange(now: context.date) ?? 0
                let stepRemaining = presetRunner.secondsUntilStepEnd(now: context.date) ?? 0
                let isLast = presetRunner.isOnLastStep
                let phase = sessionManager.currentPhase

                VStack(spacing: 6) {
                    // 上段: タイトル + ステップ/セット進捗
                    HStack(spacing: 8) {
                        Image(systemName: presetRunner.autoAdvanceEnabled ? "forward.fill" : "list.bullet.rectangle.portrait.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(preset.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("ステップ \(presetRunner.currentStepIndex + 1)/\(presetRunner.totalStepCount)")
                            .font(.caption.weight(.semibold))
                        Text("・")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("セット \(presetRunner.currentSetInStep)/\(step.setCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 下段: フェーズ残り(左) | ステップ残り(中) | 次の種目(右)
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(phaseCountdownLabel(phase: phase))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatCountdown(seconds: phaseRemaining))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundColor(phaseCountdownColor(phase: phase))
                        }

                        Divider().frame(height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(isLast ? "終了まで" : "次の種目まで")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatCountdown(seconds: stepRemaining))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(isLast ? .green : .accentColor)
                        }

                        Spacer(minLength: 4)

                        if let next = presetRunner.nextStep {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("次")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(next.exerciseName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: 90, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        )
                )
            }
        }
    }

    /// フェーズ残り時間のラベル（"休憩まで" / "筋トレまで"）
    private func phaseCountdownLabel(phase: WorkoutPhase) -> String {
        switch phase {
        case .work: return "休憩まで"
        case .rest: return "筋トレまで"
        case .idle: return ""
        }
    }

    /// フェーズ残り時間の数値カラー
    private func phaseCountdownColor(phase: WorkoutPhase) -> Color {
        switch phase {
        case .work: return .blue   // 次は休憩
        case .rest: return .red    // 次は筋トレ
        case .idle: return .secondary
        }
    }

    private func formatCountdown(seconds: Int) -> String {
        let s = max(seconds, 0)
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    // MARK: - Main Action Section (大きなアクションボタン)
    /// このセクション自体は中身（actionButtonStack）を返すだけ。
    /// 画面のどの位置（上部 / 中部 / 下部）に置くかは body 側の VStack 順序で制御する。
    private func mainActionSection(geometry: GeometryProxy) -> some View {
        let buttonWidth = effectiveWidth(geometry.size.width)
        return actionButtonStack(buttonWidth: buttonWidth)
            .frame(maxWidth: maxContentWidth)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: sessionManager.currentPhase)
    }

    /// アクションボタン本体（待機中＝スタート / 運動中＝休憩へ / 休憩中＝次のセットへ + サブボタン）
    @ViewBuilder
    private func actionButtonStack(buttonWidth: CGFloat) -> some View {
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
                    .frame(width: buttonWidth * 0.8,
                           height: min(buttonWidth * 0.55, 220))
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

                // プリセットから開始するセカンダリボタン（idle時のみ）
                Button {
                    showingPresetPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.subheadline)
                        Text("プリセットから開始")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
                    )
                }

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
                        .frame(width: buttonWidth * 0.85,
                               height: min(buttonWidth * 0.35, 140))
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
                    // 現在の状態表示（休憩時間超過時は警告表示）
                    HStack(spacing: 8) {
                        Image(systemName: sessionManager.isRestTimeExceeded ? "exclamationmark.triangle.fill" : "cup.and.saucer.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sessionManager.isRestTimeExceeded ? "休憩時間超過!" : "休憩中")
                                .font(.headline)
                                .fontWeight(.bold)
                            if sessionManager.restTimeAlertEnabled {
                                Text("目安: \(Int(sessionManager.restTimeLimit))秒")
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        // 休憩時間設定ボタン
                        Button(action: { showingRestSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(sessionManager.isRestTimeExceeded ? Color.orange.opacity(0.9) : Color.blue.opacity(0.8))
                    .cornerRadius(20)
                    .animation(.easeInOut(duration: 0.3), value: sessionManager.isRestTimeExceeded)

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
                        .frame(width: buttonWidth * 0.85,
                               height: min(buttonWidth * 0.32, 130))
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
    }

    // MARK: - Screen Time Unlock Bar (緊急解除: 常時表示・セッション中のみ)
    @ViewBuilder
    private var screenTimeUnlockBar: some View {
        if #available(iOS 16.0, *),
           sessionManager.currentPhase != .idle,
           ScreenTimeManager.shared.hasActiveShield {
            Button(action: emergencyUnlockScreenTime) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.callout)
                    Text("制限を即時解除")
                        .font(.callout)
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: "hand.raised.fill")
                        .font(.caption)
                        .opacity(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [Color.red, Color.orange], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(12)
                .shadow(color: .red.opacity(0.4), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    @available(iOS 16.0, *)
    private func emergencyUnlockScreenTime() {
        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.warning)
        ScreenTimeManager.shared.removeShield()
    }

    // MARK: - Secondary Controls Section
    private var secondaryControlsSection: some View {
        HStack(spacing: 12) {
            if sessionManager.currentPhase != .idle {
                // メモボタン（筋トレ中・休憩中いつでも押せる）
                Button(action: { showingNoteSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.callout)
                        Text("メモ")
                            .font(.callout)
                        if !noteLogger.currentSessionNotes.isEmpty {
                            Text("\(noteLogger.currentSessionNotes.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.indigo.opacity(0.75))
                    .cornerRadius(12)
                }
                .disabled(isShowingAd)

                // 完了ボタン
                Button(action: {
                    showingFinishConfirmation = true
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
                    .padding(.horizontal, 10)
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
                phaseStartDate: nil,
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
    /// 3. 広告が準備済みなら表示してリザルトへ
    /// 4. 広告ロード中なら最大5秒待機してから表示（レースコンディション対策）
    /// 5. 広告失敗時は即リザルト表示（フォールバック）
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

        print("MainTimerView: Ad state = \(adManager.state), isAdReady = \(adManager.isAdReady)")

        // 3. 広告が準備済みなら即表示
        if adManager.isAdReady {
            presentAd()
            return
        }

        // 4. 広告がロード中の場合は最大5秒待機（アプリ起動直後のレースコンディション対策）
        if case .loading = adManager.state {
            print("MainTimerView: Ad is loading, waiting up to 5s...")
            waitForAdThenShow(elapsed: 0)
            return
        }

        // 5. 広告が準備できていない場合は即リザルト（フォールバック）
        print("MainTimerView: Ad not ready (\(adManager.state)), showing summary directly (fallback)")
        showingSummary = true
        adManager.preloadAd()
    }

    /// Watch経由でセッションが終了された場合のリザルト表示処理
    /// endSession()は既にWatchConnectivityServiceで呼び出し済み
    private func handleSessionEndedFromWatch() {
        print("MainTimerView: handleSessionEndedFromWatch called")

        // 既にリザルト表示中の場合は何もしない
        guard !showingSummary else { return }

        // Proユーザーは広告をスキップ
        if proUserManager.isPro {
            print("MainTimerView: Pro user detected, skipping ad")
            showingSummary = true
            return
        }

        print("MainTimerView: Ad state = \(adManager.state), isAdReady = \(adManager.isAdReady)")

        if adManager.isAdReady {
            presentAd()
            return
        }

        if case .loading = adManager.state {
            print("MainTimerView: Ad is loading, waiting up to 5s...")
            waitForAdThenShow(elapsed: 0)
            return
        }

        print("MainTimerView: Ad not ready, showing summary")
        showingSummary = true
        adManager.preloadAd()
    }

    /// 広告をすぐに表示（isAdReady == true のときのみ呼ぶ）
    private func presentAd() {
        print("MainTimerView: Presenting rewarded ad...")
        isShowingAd = true
        showRewardedAd { success in
            DispatchQueue.main.async {
                print("MainTimerView: Ad completed with success=\(success)")
                self.isShowingAd = false
                self.showingSummary = true
            }
        }
    }

    /// 広告がロード中の場合に最大5秒ポーリングし、準備できたら表示する
    private func waitForAdThenShow(elapsed: Double) {
        // リザルトが既に表示されている場合はキャンセル
        guard !showingSummary else { return }

        let maxWait = 5.0
        let interval = 0.3

        if adManager.isAdReady {
            print("MainTimerView: Ad became ready after \(String(format: "%.1f", elapsed))s")
            presentAd()
        } else if elapsed >= maxWait {
            print("MainTimerView: Ad wait timed out after \(String(format: "%.1f", elapsed))s, showing summary")
            showingSummary = true
            adManager.preloadAd()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                self.waitForAdThenShow(elapsed: elapsed + interval)
            }
        }
    }

    /// リワード広告を表示
    private func showRewardedAd(completion: @escaping (Bool) -> Void) {
        // rootViewControllerを取得
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.keyWindow?.rootViewController else {
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
    @State private var showingAddExercise = false

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
                    // 種目追加ボタン
                    Button(action: { showingAddExercise = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            Text("新しい種目を追加")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddExercise = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                QuickAddExerciseView(
                    preselectedCategory: selectedCategory.isEmpty ? sessionManager.selectedCategory : selectedCategory
                )
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

// MARK: - Quick Add Exercise View (種目選択画面からの簡易追加)
struct QuickAddExerciseView: View {
    @Environment(\.dismiss) var dismiss

    let preselectedCategory: String

    @State private var name: String = ""
    @State private var selectedCategory: ExerciseCategory = .chest
    @State private var loadUnit: String = "kg"
    @State private var repsUnit: String = "回"
    @State private var defaultLoad: Double = 20
    @State private var defaultReps: Double = 10

    private var dataController: DataController {
        DataController.shared
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("種目名")) {
                    TextField("種目名を入力", text: $name)
                }

                Section(header: Text("カテゴリー")) {
                    Picker("カテゴリー", selection: $selectedCategory) {
                        ForEach(ExerciseCategory.allCases) { category in
                            Label {
                                Text(category.displayName)
                            } icon: {
                                Image(systemName: category.icon)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section(header: Text("デフォルト値")) {
                    HStack {
                        Text("負荷")
                        Spacer()
                        TextField("", value: $defaultLoad, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text(loadUnit)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("回数")
                        Spacer()
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                        Text(repsUnit)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("単位設定")) {
                    HStack {
                        Text("負荷単位")
                        Spacer()
                        TextField("kg", text: $loadUnit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("回数単位")
                        Spacer()
                        TextField("回", text: $repsUnit)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle("種目追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        addExercise()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                // プリセレクトされたカテゴリーを設定
                selectedCategory = ExerciseCategory.from(string: preselectedCategory)
            }
        }
    }

    private func addExercise() {
        let context = dataController.container.viewContext
        let exercise = ExerciseMaster(context: context)
        exercise.id = UUID()
        exercise.name = name
        exercise.category = selectedCategory.rawValue
        exercise.loadUnit = loadUnit
        exercise.repsUnit = repsUnit
        exercise.defaultLoad = defaultLoad
        exercise.defaultReps = defaultReps
        exercise.isActive = true
        dataController.save()
    }
}

// MARK: - Rest Time Settings Sheet
struct RestTimeSettingsSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedTime: TimeInterval = 60

    private let presetTimes: [TimeInterval] = [30, 45, 60, 90, 120, 180]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("休憩時間の目安")) {
                    // プリセットボタン
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(presetTimes, id: \.self) { time in
                            Button(action: {
                                selectedTime = time
                                sessionManager.restTimeLimit = time
                            }) {
                                Text(formatRestTime(time))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(selectedTime == time ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedTime == time ? .white : .primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section(header: Text("カスタム設定")) {
                    HStack {
                        Text("休憩時間:")
                        Spacer()
                        Text("\(Int(selectedTime))秒")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }

                    Slider(value: $selectedTime, in: 10...300, step: 5)
                        .onChange(of: selectedTime) { _, newValue in
                            sessionManager.restTimeLimit = newValue
                        }
                }

                Section(header: Text("通知設定")) {
                    Toggle("休憩時間超過アラート", isOn: $sessionManager.restTimeAlertEnabled)

                    if sessionManager.restTimeAlertEnabled {
                        Text("休憩時間が設定値を超えると、バイブレーションと通知でお知らせします。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("心拍数自動判別")) {
                    Toggle("自動フェーズ検出", isOn: $sessionManager.autoPhaseDetectionEnabled)

                    if sessionManager.autoPhaseDetectionEnabled {
                        HStack {
                            Text("安静時心拍数:")
                            Spacer()
                            Text("\(Int(sessionManager.heartRateBaseline)) bpm")
                                .foregroundColor(.blue)
                        }

                        Stepper(value: $sessionManager.heartRateBaseline, in: 40...100, step: 5) {
                            EmptyView()
                        }

                        Text("心拍数の変化から運動/休憩状態を自動検出し、フェーズ切り替えを提案します。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💡 休憩時間の目安")
                            .font(.headline)

                        Text("• 筋肥大目的: 60〜90秒")
                            .font(.caption)
                        Text("• 筋力向上目的: 2〜3分")
                            .font(.caption)
                        Text("• 持久力向上: 30〜45秒")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("休憩時間設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            selectedTime = sessionManager.restTimeLimit
        }
    }

    private func formatRestTime(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        if secs >= 60 {
            let mins = secs / 60
            let remainingSecs = secs % 60
            if remainingSecs == 0 {
                return "\(mins)分"
            } else {
                return "\(mins)分\(remainingSecs)秒"
            }
        } else {
            return "\(secs)秒"
        }
    }
}

// MARK: - Workout Note Sheet (メモ入力画面)
struct WorkoutNoteSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @ObservedObject private var noteLogger = WorkoutNoteLogger.shared
    @Environment(\.dismiss) var dismiss

    @State private var noteText: String = ""
    @State private var showingExercisePicker = false
    @State private var showingDetailInput = false
    @FocusState private var isTextEditorFocused: Bool

    private let presets: [String] = [
        "フォームが崩れた",
        "重量を上げたい",
        "限界近い",
        "呼吸が乱れた",
        "調子が良い"
    ]

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    currentStatusHeader
                    exerciseEditSection
                    noteInputSection
                    presetSection
                    historySection
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("メモを残す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        Text("保存")
                            .fontWeight(.bold)
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // シート表示直後にキーボードを出す
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isTextEditorFocused = true
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExerciseSelectionSheet()
                    .environmentObject(sessionManager)
            }
            .sheet(isPresented: $showingDetailInput) {
                ExerciseInputSheet()
                    .environmentObject(sessionManager)
            }
        }
    }

    // MARK: - Subviews
    private var currentStatusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: phaseIcon)
                .font(.title2)
                .foregroundColor(phaseColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.headline)
                if sessionManager.currentPhase != .idle {
                    Text("Cycle \(sessionManager.cycleIndex + 1)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("\(Int(heartRateManager.currentHeartRate))")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                Text("bpm")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Exercise Edit Section (種目・回数・重量の編集)
    private var exerciseEditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目標を調整")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingDetailInput = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("詳細入力")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            // 種目ボタン（カテゴリー/種目をタップで変更）
            Button(action: { showingExercisePicker = true }) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionManager.selectedCategory)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(sessionManager.selectedExercise)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // 回数 / 重量 の ±1 / ±5 行
            HStack(spacing: 8) {
                counterRow(
                    label: "回数",
                    valueText: "\(Int(sessionManager.currentReps))\(sessionManager.repsUnit)",
                    color: .green,
                    onAdjust: { delta in adjustReps(delta) }
                )
                counterRow(
                    label: "重量",
                    valueText: "\(String(format: "%.1f", sessionManager.currentLoad))\(sessionManager.loadUnit)",
                    color: .blue,
                    onAdjust: { delta in adjustLoad(delta) }
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func counterRow(
        label: String,
        valueText: String,
        color: Color,
        onAdjust: @escaping (Double) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(valueText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 4) {
                counterButton("-5", color: .red) { onAdjust(-5) }
                counterButton("-1", color: .orange) { onAdjust(-1) }
                counterButton("+1", color: .green.opacity(0.75)) { onAdjust(1) }
                counterButton("+5", color: .green) { onAdjust(5) }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func counterButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Note Input Section
    private var noteInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("メモ")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $noteText)
                    .focused($isTextEditorFocused)
                    .frame(minHeight: 100, maxHeight: 160)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                if noteText.isEmpty {
                    Text("例: フォームが崩れた / 調子が良い")
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Preset Section
    private var presetSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    Button(action: {
                        if noteText.isEmpty {
                            noteText = preset
                        } else {
                            noteText += (noteText.hasSuffix("\n") ? "" : "\n") + preset
                        }
                    }) {
                        Text(preset)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }

    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("このセッションのメモ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(noteLogger.currentSessionNotes.count)件")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            if noteLogger.currentSessionNotes.isEmpty {
                HStack {
                    Spacer()
                    Text("まだメモはありません")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.vertical, 16)
                    Spacer()
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(noteLogger.currentSessionNotes.reversed()) { entry in
                        noteRow(entry)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ entry: WorkoutNoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.phase == "work" ? "筋トレ" : entry.phase == "rest" ? "休憩" : entry.phase)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(entry.phase == "work" ? .red : .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((entry.phase == "work" ? Color.red : Color.blue).opacity(0.12))
                    .cornerRadius(4)
                if entry.heartRate > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                        Text("\(Int(entry.heartRate))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            Text(entry.text)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers
    private var phaseLabel: String {
        switch sessionManager.currentPhase {
        case .idle: return "待機中"
        case .work: return "筋トレ中"
        case .rest: return "休憩中"
        }
    }

    private var phaseIcon: String {
        switch sessionManager.currentPhase {
        case .idle: return "house.fill"
        case .work: return "figure.strengthtraining.traditional"
        case .rest: return "cup.and.saucer.fill"
        }
    }

    private var phaseColor: Color {
        switch sessionManager.currentPhase {
        case .idle: return .gray
        case .work: return .red
        case .rest: return .blue
        }
    }

    private func adjustReps(_ delta: Double) {
        let newValue = max(1, sessionManager.currentReps + delta)
        sessionManager.currentReps = newValue
        // 進行中の SetRecord にも即時反映（フェーズ終了時の補完データを正しく保つ）
        if let record = sessionManager.currentSetRecord {
            record.reps = newValue
        }
    }

    private func adjustLoad(_ delta: Double) {
        let newValue = max(0, sessionManager.currentLoad + delta)
        sessionManager.currentLoad = newValue
        if let record = sessionManager.currentSetRecord {
            record.load = newValue
        }
    }

    private func save() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = sessionManager.addQuickNote(trimmed)
        noteText = ""
        dismiss()
    }
}
