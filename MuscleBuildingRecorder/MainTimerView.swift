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
    // 筋トレ移行時の確認シート
    @State private var dontAskTransitionAgain = false
    // 次セット編集用バインディング（確認シートで編集可能）
    @State private var nextCategory: String = ""
    @State private var nextExercise: String = ""
    @State private var nextReps: Double = 10
    @State private var nextLoad: Double = 40
    @State private var nextSubject: String = ""      // study 用
    @State private var nextProject: String = ""      // work 用
    @State private var nextTaskName: String = ""     // study/work 用
    @State private var nextProgress: Double = 0      // study/work 用 (0-100)
    @State private var nextMemo: String = ""         // study/work 用
    // 前セット編集シート
    @State private var showingPreviousSetEdit = false
    @State private var prevExercise: String = ""
    @State private var prevCategory: String = ""
    @State private var prevReps: Double = 0
    @State private var prevLoad: Double = 0
    @State private var prevTaskName: String = ""
    @State private var prevProgress: Double = 0      // study/work 用
    @State private var prevMemo: String = ""         // study/work 用
    // 休憩中インライン入力: 前セットへのタグフィードバック（lastWorkRecord.payload.tagsと同期）
    @State private var selectedRestTags: Set<String> = []
    @State private var restQuickMemo: String = ""
    /// 前セットの肉体的疲労度（1-5、nil なら未入力）。lastWorkRecord.payload.rpe と同期。
    @State private var restPhysicalRpe: Int? = nil
    /// 前セットの精神的疲労度（1-5、nil なら未入力）。lastWorkRecord.payload.mentalRpe と同期。
    @State private var restMentalRpe: Int? = nil
    @State private var restCentricInitialized: Bool = false  // 休憩開始毎に1度だけ初期化
    /// セッション進捗画面の表示状態（ボタン移動のみ。横スワイプ TabView は廃止）
    @State private var showingSessionProgress: Bool = false
    @State private var showingTransitionAlert: Bool = false
    @State private var showingTagSettings: Bool = false       // タグ追加・並び替え画面
    @State private var showingTaskMasterSelection: Bool = false // 勉強/仕事のタスクマスタ選択
    @ObservedObject private var tagPresetStore = TagPresetStore.shared

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
            // 背景は root ZStack に1回だけ配置し safe area まで広げる（上下の白縁対策）。
            // 進捗画面へはボタン移動のみ（横スワイプ TabView は廃止）。
            ZStack {
                animatedBackground
                    .ignoresSafeArea()

                Group {
                    if showingSessionProgress && sessionManager.currentPhase != .idle {
                        sessionProgressScreen(geometry: geometry)
                            .transition(.move(edge: .trailing))
                    } else if sessionManager.currentPhase == .rest {
                        restCentricBody(geometry: geometry)
                    } else {
                        legacyBody(geometry: geometry)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showingSessionProgress)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if presetRunner.isRunning {
                presetProgressBanner
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showingInputSheet, onDismiss: {
            // 休憩中インライン入力の next 値を最新の入力内容へ同期
            if sessionManager.currentPhase == .rest {
                nextCategory = sessionManager.selectedCategory
                nextExercise = sessionManager.selectedExercise
                nextReps = sessionManager.currentReps
                nextLoad = sessionManager.currentLoad
                nextSubject = sessionManager.currentSubject
                nextProject = sessionManager.currentProject
                nextTaskName = sessionManager.currentTaskName
            }
        }) {
            switch sessionManager.activeDomain {
            case .workout:
                ExerciseInputSheet()
                    .environmentObject(sessionManager)
            case .study, .work:
                TaskInputSheet(domain: sessionManager.activeDomain)
                    .environmentObject(sessionManager)
            }
        }
        .sheet(isPresented: $showingExerciseSelection, onDismiss: {
            // 休憩中インライン入力の next 値を最新の選択へ同期
            if sessionManager.currentPhase == .rest {
                nextCategory = sessionManager.selectedCategory
                nextExercise = sessionManager.selectedExercise
                nextReps = sessionManager.currentReps
                nextLoad = sessionManager.currentLoad
            }
        }) {
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
        .sheet(isPresented: $showingPreviousSetEdit) {
            previousSetEditSheet
        }
        .sheet(isPresented: $showingTagSettings) {
            TagPresetSettingsView()
        }
        .sheet(isPresented: $showingTaskMasterSelection, onDismiss: {
            // 休憩中インライン入力の next 値を最新の選択へ同期
            if sessionManager.currentPhase == .rest {
                nextSubject = sessionManager.currentSubject
                nextProject = sessionManager.currentProject
                nextTaskName = sessionManager.currentTaskName
                nextProgress = sessionManager.currentProgress
            }
        }) {
            if sessionManager.activeDomain != .workout {
                TaskMasterSelectionSheet(domain: sessionManager.activeDomain)
                    .environmentObject(sessionManager)
            }
        }
        .fullScreenCover(isPresented: $showingSummary) {
            SessionSummaryView()
                .environmentObject(sessionManager)
                .environmentObject(proUserManager)
        }
        .alert("トレーニング終了", isPresented: $showingFinishConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("終了する", role: .destructive) { finishWorkoutWithAdGate() }
        } message: {
            Text("トレーニングを終了しますか？\n\n総時間: \(formatTime(sessionManager.elapsedTime))\n筋トレ: \(formatTime(sessionManager.totalWorkTime))\n休憩: \(formatTime(sessionManager.totalRestTime))")
        }
        .alert(sessionManager.activeDomain.workPhaseLabel + "を開始しますか?", isPresented: $showingTransitionAlert) {
            Button("キャンセル", role: .cancel) {
                sessionManager.cancelTransitionToWork()
            }
            Button("次の\(sessionManager.activeDomain.workPhaseLabel)設定") {
                // まだ開始せず、進捗画面で次セットを調整する。
                // pending（Watch 起点）の場合は flag を戻し Watch を rest に再同期。
                sessionManager.cancelTransitionToWork()
                openSessionProgress()
            }
            Button("開始") {
                commitNextSetAndStart()
            }
        } message: {
            Text(transitionAlertMessage)
        }
        .onChange(of: sessionManager.pendingTransitionToWork) { pending in
            if pending {
                primeNextSetEditing()
                showingTransitionAlert = true
            }
        }
        .onChange(of: sessionManager.currentPhase) { newPhase in
            if newPhase == .rest {
                primeRestCentricInputs()
            } else {
                restCentricInitialized = false
            }
            // idle（セッション終了）になったら進捗画面を確実に閉じる（完了サマリとの被り防止）
            if newPhase == .idle {
                showingSessionProgress = false
            }
        }
        .onReceive(watchConnectivity.$showExerciseSelectionRequested) { requested in
            if requested {
                showingExerciseSelection = true
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
            setupSessionObservers()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
            requestNotificationPermission()
            if sessionManager.currentPhase == .rest { primeRestCentricInputs() }
        }
    }

    // MARK: - Legacy Body (idle / work 時の従来レイアウト)
    @ViewBuilder
    private func legacyBody(geometry: GeometryProxy) -> some View {
        let position = effectiveButtonPosition
        legacyBodyContent(geometry: geometry, position: position)
    }

    @ViewBuilder
    private func legacyBodyContent(geometry: GeometryProxy, position: MainButtonVerticalPosition) -> some View {
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
        .animation(.easeInOut(duration: 0.25), value: position)
    }

    // MARK: - Rest-Centric Layout (休憩中の主操作画面)

    /// 休憩中の専用レイアウト: タイマー + 前セット編集（中央メイン）+ 次セット設定ボタン + CTA + 完了
    @ViewBuilder
    private func restCentricBody(geometry: GeometryProxy) -> some View {
        VStack(spacing: 6) {
            statusHeaderSection
                .frame(height: geometry.size.height * 0.09)
            restTimerHeroSection
                .frame(height: geometry.size.height * 0.18)
                .padding(.horizontal, 12)
            ScrollView {
                previousSetCentralEditor
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            nextSetSettingsButton
                .padding(.horizontal, 12)
            nextSetCTASection(buttonWidth: effectiveWidth(geometry.size.width))
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            finishButtonCompact
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    /// 休憩中の中央メイン: 前セット（実績）を編集できるエリア。
    /// 拡大カード（タップで `previousSetEditSheet`）＋ タグ/RPE/メモ（いずれも前セットへのフィードバック）。
    private var previousSetCentralEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "clock.arrow.circlepath", text: "前の\(sessionManager.activeDomain.workPhaseLabel)")
            previousSetCentralCard
            // タグ群
            tagSectionHeader
            tagChipRow
            // F-2: RPE（前セットの肉体的・精神的疲労度）— workout のみ表示
            if sessionManager.activeDomain == .workout {
                rpeSection
            }
            // クイックメモ
            sectionHeader(icon: "square.and.pencil", text: "メモ")
            quickMemoField
        }
        .padding(.vertical, 6)
    }

    /// 前セットの拡大カード（タップで編集シートを開く）。未記録時はプレースホルダ。
    @ViewBuilder
    private var previousSetCentralCard: some View {
        if let record = sessionManager.lastWorkRecord {
            Button(action: openPreviousSetEdit) {
                HStack(spacing: 10) {
                    previousSetCompactDescription(for: record)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.25))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("最初の\(sessionManager.activeDomain.workPhaseLabel)後にここに表示されます")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.15))
            .cornerRadius(12)
        }
    }

    /// 進捗画面（次セット設定）へ移動するボタン。
    private var nextSetSettingsButton: some View {
        Button(action: openSessionProgress) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.callout)
                Text("次の\(sessionManager.activeDomain.workPhaseLabel)設定")
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    /// 休憩開始時に呼ばれる初期化処理。前セット実績の payload・current 値をUIへ反映。
    private func primeRestCentricInputs() {
        guard !restCentricInitialized else { return }
        restCentricInitialized = true
        primeNextSetEditing()
        // 前セットがあれば既存タグ・メモ・RPE を読み込み
        if let record = sessionManager.lastWorkRecord {
            let payload = record.payload
            selectedRestTags = Set(payload.tags)
            restQuickMemo = payload.memo
            restPhysicalRpe = payload.rpe
            restMentalRpe = payload.mentalRpe
        } else {
            selectedRestTags = []
            restQuickMemo = ""
            restPhysicalRpe = nil
            restMentalRpe = nil
        }
    }

    // MARK: Rest sections

    private var restTimerHeroSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("休憩中")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text(timerText)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if sessionManager.restTimeAlertEnabled {
                    HStack(spacing: 4) {
                        Text("目安 \(Int(sessionManager.restTimeLimit))秒")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        if sessionManager.currentRestSnoozeOffset > 0 {
                            Text("(+\(Int(sessionManager.currentRestSnoozeOffset))s)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            Spacer()
            Button(action: snoozeRest) {
                VStack(spacing: 2) {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                    Text("+30s")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle().fill(Color.orange.opacity(0.85))
                        .shadow(color: .orange.opacity(0.5), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.blue.opacity(0.25))
        )
    }

    private func snoozeRest() {
        // SessionManager.snoozeRest を呼ぶことで、予鈴・本鈴フラグもリセットされ
        // 延長後に再度通知が鳴るようになる（F-1）。
        sessionManager.snoozeRest(by: 30)
    }

    @ViewBuilder
    private func previousSetCompactDescription(for record: SetRecord) -> some View {
        switch sessionManager.activeDomain {
        case .workout:
            HStack(spacing: 4) {
                Text(record.name ?? "-")
                    .font(.caption).foregroundColor(.white)
                Text("\(Int(record.reps))×\(String(format: "%.1f", record.load))")
                    .font(.caption).fontWeight(.bold).foregroundColor(.yellow)
            }
        case .study, .work:
            HStack(spacing: 6) {
                Text(record.taskName ?? "-")
                    .font(.caption).foregroundColor(.yellow).lineLimit(1)
                Text("\(Int(record.focusScore))%")
                    .font(.caption2).foregroundColor(.white.opacity(0.8))
            }
        }
    }

    // MARK: Inline next-set form

    private var inlineNextSetForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(icon: "arrow.forward.circle.fill", text: "次の\(sessionManager.activeDomain.workPhaseLabel)")
            switch sessionManager.activeDomain {
            case .workout:
                inlineWorkoutFields
            case .study:
                inlineStudyFields
            case .work:
                inlineWorkFields
            }
        }
        .padding(.vertical, 6)
    }

    /// F-2: RPE 入力（Physical / Mental の 2 軸、1-5 スケール）
    @ViewBuilder
    private var rpeSection: some View {
        sectionHeader(icon: "gauge.with.dots.needle.50percent", text: "前セットの疲労度（RPE）")
        VStack(spacing: 8) {
            rpePicker(
                label: "肉体的",
                icon: "figure.strengthtraining.traditional",
                value: $restPhysicalRpe,
                accent: .red
            )
            rpePicker(
                label: "精神的",
                icon: "brain.head.profile",
                value: $restMentalRpe,
                accent: .purple
            )
        }
    }

    @ViewBuilder
    private func rpePicker(label: String, icon: String, value: Binding<Int?>, accent: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(accent)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 64, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        // タップで切替（同じ値を再タップしたらクリア）
                        if value.wrappedValue == level {
                            value.wrappedValue = nil
                        } else {
                            value.wrappedValue = level
                        }
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        syncTagsAndMemoToLastRecord()
                    } label: {
                        Text("\(level)")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .foregroundColor(value.wrappedValue == level ? .black : .white)
                            .background(
                                Capsule().fill(value.wrappedValue == level
                                               ? accent.opacity(0.85)
                                               : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionManager.lastWorkRecord == nil)
                }
            }
        }
        .opacity(sessionManager.lastWorkRecord == nil ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func sectionHeader(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption)
            Spacer()
        }
        .foregroundColor(.white.opacity(0.75))
        .padding(.top, 4)
    }

    @ViewBuilder
    private var inlineWorkoutFields: some View {
        // 種目選択（タップで ExerciseSelectionSheet を開く）
        Button(action: { showingExerciseSelection = true }) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextCategory.isEmpty ? sessionManager.selectedCategory : nextCategory)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    Text(nextExercise.isEmpty ? sessionManager.selectedExercise : nextExercise)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)

        // 回数 / 重量: 増減ボタン + スライダー
        HStack(spacing: 8) {
            restCounterRow(
                label: "回数",
                valueText: "\(Int(nextReps))\(sessionManager.repsUnit)",
                color: .green,
                value: $nextReps,
                range: 1...100,
                step: 1
            )
            restCounterRow(
                label: "重量",
                valueText: "\(String(format: "%.1f", nextLoad))\(sessionManager.loadUnit)",
                color: .blue,
                value: $nextLoad,
                range: 0...200,
                step: restLoadStep
            )
        }
    }

    private var restLoadStep: Double {
        switch sessionManager.loadUnit {
        case "kg": return 1
        case "W": return 10
        case "レベル": return 1
        default: return 1
        }
    }

    @ViewBuilder
    private func restCounterRow(
        label: String,
        valueText: String,
        color: Color,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(valueText)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                restCounterButton("-5", color: .red) { adjustNextValue(value, delta: -5, range: range) }
                restCounterButton("-1", color: .orange) { adjustNextValue(value, delta: -1, range: range) }
                restCounterButton("+1", color: .green.opacity(0.75)) { adjustNextValue(value, delta: 1, range: range) }
                restCounterButton("+5", color: .green) { adjustNextValue(value, delta: 5, range: range) }
            }
            Slider(value: value, in: range, step: step)
                .tint(color)
        }
        .padding(8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }

    private func restCounterButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
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

    private func adjustNextValue(_ binding: Binding<Double>, delta: Double, range: ClosedRange<Double>) {
        let newValue = min(max(binding.wrappedValue + delta, range.lowerBound), range.upperBound)
        binding.wrappedValue = newValue
    }

    @ViewBuilder
    private var inlineStudyFields: some View {
        taskSelectionCard(
            iconName: "book.fill",
            iconColor: .blue,
            secondaryLabel: "科目",
            secondary: nextSubject.isEmpty ? sessionManager.currentSubject : nextSubject,
            primaryPlaceholder: "タップして勉強内容を入力",
            primary: nextTaskName.isEmpty ? sessionManager.currentTaskName : nextTaskName
        )
        inlineHistoryChips(domain: "study", parent: nextSubject, binding: $nextTaskName)
        restCounterRow(
            label: "進行度",
            valueText: "\(Int(nextProgress))%",
            color: .blue,
            value: $nextProgress,
            range: 0...100,
            step: 1
        )
    }

    @ViewBuilder
    private var inlineWorkFields: some View {
        taskSelectionCard(
            iconName: "briefcase.fill",
            iconColor: .green,
            secondaryLabel: "プロジェクト",
            secondary: nextProject.isEmpty ? sessionManager.currentProject : nextProject,
            primaryPlaceholder: "タップしてタスク名を入力",
            primary: nextTaskName.isEmpty ? sessionManager.currentTaskName : nextTaskName
        )
        inlineHistoryChips(domain: "work", parent: nextProject, binding: $nextTaskName)
        restCounterRow(
            label: "進行度",
            valueText: "\(Int(nextProgress))%",
            color: .green,
            value: $nextProgress,
            range: 0...100,
            step: 1
        )
    }

    /// 勉強/仕事ドメイン用の「タップでタスクマスタ選択を開く」カード
    @ViewBuilder
    private func taskSelectionCard(
        iconName: String,
        iconColor: Color,
        secondaryLabel: String,
        secondary: String,
        primaryPlaceholder: String,
        primary: String
    ) -> some View {
        Button(action: { showingTaskMasterSelection = true }) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(secondary.isEmpty ? "\(secondaryLabel) 未設定" : "\(secondaryLabel): \(secondary)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(primary.isEmpty ? primaryPlaceholder : primary)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inlineFieldRow<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            content()
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func inlineHistoryChips(domain: String, parent: String, binding: Binding<String>) -> some View {
        let suggestions = TaskHistoryStore.shared.suggestions(domain: domain, parent: parent)
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { name in
                        Button { binding.wrappedValue = name } label: {
                            Text(name)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Tag chips (前セットへのタグ。lastWorkRecordがあるときのみ有効)

    /// タグ行のヘッダ（タイトル + 管理ボタン）
    private var tagSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill").font(.caption)
            Text("前セットのタグ").font(.caption)
            Spacer()
            Button(action: { showingTagSettings = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("管理").font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.white.opacity(0.75))
        .padding(.top, 4)
    }

    private var tagChipRow: some View {
        let tags = tagPresetStore.tags(for: sessionManager.activeDomain.rawValue)
        let hasPrevRecord = sessionManager.lastWorkRecord != nil
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button { toggleTag(tag) } label: {
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selectedRestTags.contains(tag)
                                               ? Color.yellow
                                               : Color.white.opacity(0.18))
                            )
                            .foregroundColor(selectedRestTags.contains(tag) ? .black : .white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasPrevRecord)
                }
            }
        }
        .opacity(hasPrevRecord ? 1.0 : 0.5)
    }

    private func toggleTag(_ tag: String) {
        guard sessionManager.lastWorkRecord != nil else { return }
        if selectedRestTags.contains(tag) {
            selectedRestTags.remove(tag)
        } else {
            selectedRestTags.insert(tag)
        }
        syncTagsAndMemoToLastRecord()
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private var quickMemoField: some View {
        TextField("クイックメモ（例: 肩に違和感）", text: $restQuickMemo, axis: .vertical)
            .lineLimit(2...4)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12))
            .cornerRadius(10)
            .foregroundColor(.white)
            .onChange(of: restQuickMemo) { _ in
                syncTagsAndMemoToLastRecord()
            }
    }

    /// selectedRestTags / restQuickMemo / RPE を lastWorkRecord.payload に保存
    private func syncTagsAndMemoToLastRecord() {
        guard let record = sessionManager.lastWorkRecord else { return }
        var payload = record.payload
        payload.tags = Array(selectedRestTags)
        payload.memo = restQuickMemo
        payload.rpe = restPhysicalRpe
        payload.mentalRpe = restMentalRpe
        sessionManager.updatePreviousSetRecordPayload(payload)
    }

    // MARK: CTA & finish

    private func nextSetCTASection(buttonWidth: CGFloat) -> some View {
        Button(action: handleStartNextSet) {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 30))
                Text("次の\(sessionManager.activeDomain.workPhaseLabel)へ")
                    .font(.title3).fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: buttonWidth * 0.92)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [Color.red, Color.red.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .red.opacity(0.5), radius: 10, x: 0, y: 5)
            )
        }
    }

    /// 「次のセットへ」押下時のハンドラ。設定ONなら簡易alert、OFFなら即遷移。
    private func handleStartNextSet() {
        // インライン入力済みなので、設定 ON 時は簡易確認のみ
        if sessionManager.confirmTransitionToWork {
            showingTransitionAlert = true
        } else {
            commitNextSetAndStart()
        }
    }

    // MARK: - Session Progress Screen (次セット設定 + 進捗。ボタン移動のみ)

    /// 進捗画面を開く。次セットフォームを最新の current 値で初期化してから表示。
    private func openSessionProgress() {
        primeNextSetEditing()
        withAnimation { showingSessionProgress = true }
    }

    /// 進捗画面の「次の◯◯へ」押下: 画面を閉じてから次セットを確定・開始。
    private func handleStartNextSetFromProgress() {
        showingSessionProgress = false
        commitNextSetAndStart()
    }

    /// 進捗 + 次セット設定をまとめた画面。ProgressDashboardPage にフォーム/ボタンをクロージャ注入。
    @ViewBuilder
    private func sessionProgressScreen(geometry: GeometryProxy) -> some View {
        ProgressDashboardPage(
            geometry: geometry,
            onClose: { withAnimation { showingSessionProgress = false } },
            onStartNextSet: { handleStartNextSetFromProgress() },
            formContent: { inlineNextSetForm }
        )
        .environmentObject(sessionManager)
    }

    /// 簡易alertのメッセージ。次セットのサマリを1行で表示
    private var transitionAlertMessage: String {
        switch sessionManager.activeDomain {
        case .workout:
            return "\(nextExercise) \(Int(nextReps))回 × \(String(format: "%.1f", nextLoad))\(sessionManager.loadUnit)"
        case .study:
            return "\(nextSubject) / \(nextTaskName)"
        case .work:
            return "\(nextProject) / \(nextTaskName)"
        }
    }

    private var finishButtonCompact: some View {
        Button(action: { showingFinishConfirmation = true }) {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle.fill").font(.subheadline)
                Text("完了").font(.subheadline).fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.gray.opacity(0.6)))
        }
        .disabled(isShowingAd)
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

            // 合計時間表示（ドメインに応じて Work/Rest ラベルとアクセント色を切替）
            if sessionManager.currentPhase != .idle {
                HStack(spacing: 12) {
                    // 集中・作業・筋トレ 総時間
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: workPhaseIcon)
                                .font(.caption2)
                                .foregroundColor(domainColor(sessionManager.activeDomain))
                            Text(sessionManager.activeDomain.workPhaseLabel)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Text(formatTime(sessionManager.totalWorkTime))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(domainColor(sessionManager.activeDomain))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(domainColor(sessionManager.activeDomain).opacity(0.2))
                    .cornerRadius(8)

                    // 休憩・小休止 総時間
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                            Text(sessionManager.activeDomain.restPhaseLabel)
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
                // 種目／タスク表示エリア（タップで変更可能）
                // workout: ExerciseSelectionSheet（カテゴリ+種目）
                // study/work: TaskMasterSelectionSheet（マスタタスク選択）
                Button(action: {
                    if sessionManager.activeDomain == .workout {
                        showingExerciseSelection = true
                    } else {
                        showingTaskMasterSelection = true
                    }
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))

                        Spacer()

                        VStack(spacing: 4) {
                            Text(exerciseSectionSubtitle)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))

                            Text(exerciseSectionTitle)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        Spacer()

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
                                if sessionManager.activeDomain == .workout {
                                    showingExerciseSelection = true
                                } else {
                                    showingTaskMasterSelection = true
                                }
                            }
                        }
                )
            } else {
                // 待機中
                VStack(spacing: 4) {
                    Text(idleHeadline)
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

    /// 運動中の種目エリアの上段（カテゴリ or 科目/プロジェクト）
    private var exerciseSectionSubtitle: String {
        switch sessionManager.activeDomain {
        case .workout:
            return sessionManager.selectedCategory
        case .study:
            return sessionManager.currentSubject.isEmpty ? "科目未設定" : sessionManager.currentSubject
        case .work:
            return sessionManager.currentProject.isEmpty ? "プロジェクト未設定" : sessionManager.currentProject
        }
    }

    /// 運動中の種目エリアの下段（種目名 or タスク名）
    private var exerciseSectionTitle: String {
        switch sessionManager.activeDomain {
        case .workout:
            return sessionManager.selectedExercise
        case .study, .work:
            return sessionManager.currentTaskName.isEmpty ? "タップしてタスク名を入力" : sessionManager.currentTaskName
        }
    }

    /// idle 時のヘッドライン（ドメインによりタイトルを変更）
    private var idleHeadline: String {
        switch sessionManager.activeDomain {
        case .workout: return "筋トレ記録"
        case .study:   return "勉強記録"
        case .work:    return "仕事記録"
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
        case .work:
            // workout: セット実行中、study: 集中中、work: 作業中
            return sessionManager.activeDomain == .workout
                ? "セット実行中"
                : sessionManager.activeDomain.workPhaseLabel + "中"
        case .rest:
            return sessionManager.activeDomain.restPhaseLabel + "中"
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

            // 前セット実績カード（休憩中のみ表示）
            // ドメイン別の項目を表示。タップで前セット編集シートを開く。
            if sessionManager.currentPhase == .rest {
                previousSetSummaryCard
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

    // MARK: - Previous Set Summary Card (休憩中: 直前セットの実績表示・編集)
    @ViewBuilder
    private var previousSetSummaryCard: some View {
        if let record = sessionManager.lastWorkRecord {
            Button(action: openPreviousSetEdit) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                        Text("前の\(sessionManager.activeDomain.workPhaseLabel)実績")
                            .font(.caption)
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.7))

                    previousSetContentRow(for: record)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.25))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        } else {
            // 1セット目: 前セット未生成。次セットの確認シートでのみ編集
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("前の\(sessionManager.activeDomain.workPhaseLabel)はまだありません")
                    .font(.caption)
            }
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.15))
            .cornerRadius(16)
        }
    }

    @ViewBuilder
    private func previousSetContentRow(for record: SetRecord) -> some View {
        switch sessionManager.activeDomain {
        case .workout:
            HStack(spacing: 10) {
                Text(record.name ?? "-")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Text("\(Int(record.reps))\(sessionManager.repsUnit)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                Text("×")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text("\(String(format: "%.1f", record.load))\(sessionManager.loadUnit)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
            }
        case .study:
            VStack(spacing: 2) {
                Text(sessionManager.currentSubject.isEmpty ? "-" : sessionManager.currentSubject)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text(record.taskName ?? "(勉強内容未入力)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.yellow)
                    .lineLimit(1)
                Text("進行度 \(Int(record.focusScore))%")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        case .work:
            VStack(spacing: 2) {
                Text(sessionManager.currentProject.isEmpty ? "-" : sessionManager.currentProject)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                Text(record.taskName ?? "(タスク未入力)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.yellow)
                    .lineLimit(1)
                Text("進行度 \(Int(record.focusScore))%")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func openPreviousSetEdit() {
        guard let record = sessionManager.lastWorkRecord else { return }
        prevExercise = record.name ?? ""
        prevCategory = record.category ?? ""
        prevReps = record.reps
        prevLoad = record.load
        prevTaskName = record.taskName ?? ""
        prevProgress = record.focusScore
        prevMemo = record.note ?? ""
        showingPreviousSetEdit = true
    }

    private func savePreviousSetEdits() {
        switch sessionManager.activeDomain {
        case .workout:
            sessionManager.updatePreviousSetRecord(
                exercise: prevExercise,
                category: prevCategory,
                reps: prevReps,
                load: prevLoad
            )
        case .study, .work:
            sessionManager.updatePreviousSetRecord(
                taskName: prevTaskName,
                progress: prevProgress,
                note: prevMemo
            )
        }
        showingPreviousSetEdit = false
    }

    private var previousSetEditSheet: some View {
        NavigationStack {
            Form {
                Section("前の\(sessionManager.activeDomain.workPhaseLabel)実績") {
                    switch sessionManager.activeDomain {
                    case .workout:
                        Picker("カテゴリ", selection: $prevCategory) {
                            ForEach(sessionManager.getAvailableCategories(), id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        Picker("種目", selection: $prevExercise) {
                            ForEach(prevAvailableExercises, id: \.self) { exercise in
                                Text(exercise).tag(exercise)
                            }
                        }
                        formCounterRow(
                            label: "回数",
                            value: $prevReps,
                            unit: sessionManager.repsUnit,
                            range: 1...100,
                            step: 1,
                            color: .green,
                            valueFormat: "%.0f"
                        )
                        formCounterRow(
                            label: "重量",
                            value: $prevLoad,
                            unit: sessionManager.loadUnit,
                            range: 0...200,
                            step: restLoadStep,
                            color: .blue,
                            valueFormat: "%.1f"
                        )
                    case .study:
                        TextField("勉強内容", text: $prevTaskName)
                        taskHistorySuggestions(domain: "study", parent: sessionManager.currentSubject, binding: $prevTaskName)
                        formCounterRow(
                            label: "進行度",
                            value: $prevProgress,
                            unit: "%",
                            range: 0...100,
                            step: 1,
                            color: .blue,
                            valueFormat: "%.0f"
                        )
                        memoEditor(text: $prevMemo)
                    case .work:
                        TextField("タスク", text: $prevTaskName)
                        taskHistorySuggestions(domain: "work", parent: sessionManager.currentProject, binding: $prevTaskName)
                        formCounterRow(
                            label: "進行度",
                            value: $prevProgress,
                            unit: "%",
                            range: 0...100,
                            step: 1,
                            color: .green,
                            valueFormat: "%.0f"
                        )
                        memoEditor(text: $prevMemo)
                    }
                }
            }
            .navigationTitle("実績を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingPreviousSetEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { savePreviousSetEdits() }
                        .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// previousSetEditSheet 内 Picker 用: prevCategory に基づく種目候補
    private var prevAvailableExercises: [String] {
        let category = prevCategory.isEmpty ? sessionManager.selectedCategory : prevCategory
        return sessionManager.getExercises(for: category)
    }

    /// Form 内向け: ラベル + 増減ボタン + スライダーの行
    @ViewBuilder
    private func formCounterRow(
        label: String,
        value: Binding<Double>,
        unit: String,
        range: ClosedRange<Double>,
        step: Double,
        color: Color,
        valueFormat: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text("\(String(format: valueFormat, value.wrappedValue))\(unit)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                formCounterButton("-5", color: .red) { adjustNextValue(value, delta: -5, range: range) }
                formCounterButton("-1", color: .orange) { adjustNextValue(value, delta: -1, range: range) }
                formCounterButton("+1", color: .green.opacity(0.75)) { adjustNextValue(value, delta: 1, range: range) }
                formCounterButton("+5", color: .green) { adjustNextValue(value, delta: 5, range: range) }
            }
            Slider(value: value, in: range, step: step)
                .tint(color)
        }
        .padding(.vertical, 4)
    }

    private func formCounterButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 12) {
            if sessionManager.currentPhase == .idle {
                // モード切替（筋トレ / 勉強 / 仕事）
                domainPicker

                // 待機中: 大きなスタートボタン
                Button(action: startSessionWithWatchCheck) {
                    VStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                        Text("スタート")
                            .font(.title)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth * 0.75,
                           height: min(buttonWidth * 0.42, 160))
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
                    // 現在の状態表示（ドメインに応じてラベルとアイコンを切替）
                    HStack(spacing: 8) {
                        Image(systemName: workPhaseIcon)
                            .font(.title2)
                        Text(sessionManager.activeDomain.workPhaseLabel + "中")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(domainColor(sessionManager.activeDomain))
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

                    // 筋トレボタン（大）— 確認設定ONなら確認ダイアログを経由
                    Button(action: requestTransitionToWork) {
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

                    // 前セット実績は中央カードから、次セット内容は「次のセットへ」の確認シートで編集
                }
            }
        }
    }

    // MARK: - Domain Picker (idle 時のモード切替)
    private var domainPicker: some View {
        HStack(spacing: 8) {
            ForEach(ActivityDomain.allCases, id: \.self) { domain in
                Button {
                    if sessionManager.activeDomain != domain {
                        sessionManager.activeDomain = domain
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: domain.iconName)
                            .font(.subheadline)
                        Text(domain.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(sessionManager.activeDomain == domain ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(sessionManager.activeDomain == domain ? domainColor(domain) : Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func domainColor(_ domain: ActivityDomain) -> Color {
        switch domain {
        case .workout: return Color.red.opacity(0.8)
        case .study:   return Color.blue.opacity(0.8)
        case .work:    return Color.green.opacity(0.8)
        }
    }

    /// 運動中ステータス表示のアイコン（ドメイン別）
    private var workPhaseIcon: String {
        switch sessionManager.activeDomain {
        case .workout: return "figure.strengthtraining.traditional"
        case .study:   return "book.fill"
        case .work:    return "briefcase.fill"
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

            // パルスエフェクト（運動中のみ。ドメインに応じて色を変更）
            if sessionManager.currentPhase == .work {
                Circle()
                    .fill(domainColor(sessionManager.activeDomain).opacity(0.1))
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
                // ドメインに応じて作業中グラデーションを切替
                switch sessionManager.activeDomain {
                case .workout:
                    return [Color(red: 0.7, green: 0.15, blue: 0.15),
                            Color(red: 0.4, green: 0.08, blue: 0.08)]
                case .study:
                    return [Color(red: 0.15, green: 0.25, blue: 0.7),
                            Color(red: 0.08, green: 0.15, blue: 0.4)]
                case .work:
                    return [Color(red: 0.15, green: 0.55, blue: 0.25),
                            Color(red: 0.08, green: 0.30, blue: 0.15)]
                }
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

    // MARK: - Transition Confirmation
    /// 旧モーダル用に残してあったエントリ。現在は restCentricBody から直接 handleStartNextSet を使う。
    /// 互換のためメソッドだけ残置（一部呼び出し元が legacyBody 経由で残っている場合がある）。
    private func requestTransitionToWork() {
        let immediate = sessionManager.requestTransitionToWork(notifyWatch: true)
        if !immediate {
            primeNextSetEditing()
            showingTransitionAlert = true
        }
    }

    /// 確認シート編集用 @State を SessionManager の current Xxx 系で初期化
    private func primeNextSetEditing() {
        dontAskTransitionAgain = false
        nextCategory = sessionManager.selectedCategory
        nextExercise = sessionManager.selectedExercise
        nextReps = sessionManager.currentReps
        nextLoad = sessionManager.currentLoad
        nextSubject = sessionManager.currentSubject
        nextProject = sessionManager.currentProject
        nextTaskName = sessionManager.currentTaskName
        nextProgress = sessionManager.currentProgress
        nextMemo = sessionManager.currentMemo
    }

    /// 「開始」押下時：編集値を SessionManager に反映してから遷移
    private func commitNextSetAndStart() {
        switch sessionManager.activeDomain {
        case .workout:
            sessionManager.selectedCategory = nextCategory
            sessionManager.selectedExercise = nextExercise
            sessionManager.currentReps = nextReps
            sessionManager.currentLoad = nextLoad
        case .study:
            sessionManager.currentSubject = nextSubject
            sessionManager.currentTaskName = nextTaskName
            sessionManager.currentProgress = nextProgress
            sessionManager.currentMemo = nextMemo
            // 履歴に taskName を記憶
            if !nextTaskName.isEmpty {
                TaskHistoryStore.shared.remember(domain: "study", parent: nextSubject, taskName: nextTaskName)
            }
        case .work:
            sessionManager.currentProject = nextProject
            sessionManager.currentTaskName = nextTaskName
            sessionManager.currentProgress = nextProgress
            sessionManager.currentMemo = nextMemo
            if !nextTaskName.isEmpty {
                TaskHistoryStore.shared.remember(domain: "work", parent: nextProject, taskName: nextTaskName)
            }
        }
        showingTransitionAlert = false
        showingSessionProgress = false
        sessionManager.confirmTransitionToWorkConfirmed(dontAskAgain: dontAskTransitionAgain)
    }

    // 旧モーダル確認シートは撤去。restCentricBody がインライン入力を兼ねるため不要。

    @ViewBuilder
    private var workoutNextSetFields: some View {
        TextField("カテゴリ", text: $nextCategory)
        TextField("種目", text: $nextExercise)
        HStack {
            Text("回数")
            Spacer()
            TextField("回数", value: $nextReps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(sessionManager.repsUnit)
                .foregroundColor(.secondary)
        }
        HStack {
            Text("重量")
            Spacer()
            TextField("重量", value: $nextLoad, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(sessionManager.loadUnit)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var studyNextSetFields: some View {
        TextField("科目", text: $nextSubject)
        TextField("勉強内容", text: $nextTaskName)
        taskHistorySuggestions(domain: "study", parent: nextSubject, binding: $nextTaskName)
        progressEditor(value: $nextProgress)
        memoEditor(text: $nextMemo)
    }

    @ViewBuilder
    private var workNextSetFields: some View {
        TextField("プロジェクト", text: $nextProject)
        TextField("タスク", text: $nextTaskName)
        taskHistorySuggestions(domain: "work", parent: nextProject, binding: $nextTaskName)
        progressEditor(value: $nextProgress)
        memoEditor(text: $nextMemo)
    }

    /// 履歴サジェスト表示。parent に紐づく taskName を最新順に表示し、タップで binding に反映
    @ViewBuilder
    private func taskHistorySuggestions(domain: String, parent: String, binding: Binding<String>) -> some View {
        let suggestions = TaskHistoryStore.shared.suggestions(domain: domain, parent: parent)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近の入力")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { binding.wrappedValue = name } label: {
                                Text(name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// 進行度スライダー（0–100）
    @ViewBuilder
    private func progressEditor(value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("進行度")
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1)
        }
    }

    /// メモ入力欄（複数行）
    @ViewBuilder
    private func memoEditor(text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("メモ")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("メモを入力", text: text, axis: .vertical)
                .lineLimit(2...5)
        }
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

        // 進捗画面が開いていても確実に閉じてから完了サマリを出す（被り防止）
        showingSessionProgress = false

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

        // 進捗画面が開いていても確実に閉じる（被り防止）
        showingSessionProgress = false

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

// MARK: - U-3: Progress Dashboard Page
/// セッション中にタイマー画面から横スワイプで表示される進捗ダッシュボード。
/// - 経過時間（円形プログレス）
/// - 完了セット数（work record の数）
/// - 総ボリューム（workout のみ）
/// - 筋トレ時間 / 休憩時間
/// - 平均/最大心拍数
struct ProgressDashboardPage<FormContent: View>: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject private var heartRateManager = HeartRateManager.shared
    let geometry: GeometryProxy
    let onClose: () -> Void
    let onStartNextSet: () -> Void
    @ViewBuilder let formContent: () -> FormContent

    init(
        geometry: GeometryProxy,
        onClose: @escaping () -> Void,
        onStartNextSet: @escaping () -> Void,
        @ViewBuilder formContent: @escaping () -> FormContent
    ) {
        self.geometry = geometry
        self.onClose = onClose
        self.onStartNextSet = onStartNextSet
        self.formContent = formContent
    }

    private var workRecords: [SetRecord] {
        guard let session = sessionManager.currentSession,
              let records = session.setRecords?.allObjects as? [SetRecord] else { return [] }
        return records.filter { $0.phase == "Work" }
    }

    private var completedWorkSets: Int {
        // 進行中の work record も含めるため、cycleIndex + 1（rest 中は cycleIndex 個完了済み）
        // ただし phase によって扱いが異なるため work record 件数を信頼する
        workRecords.filter { $0.endAt != nil }.count
    }

    private var totalVolume: Double {
        workRecords.reduce(0) { $0 + ($1.load * $1.reps) }
    }

    private var avgHeartRate: Double {
        let valid = workRecords.compactMap { $0.hrAvg > 0 ? $0.hrAvg : nil }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    private var maxHeartRate: Double {
        workRecords.compactMap { $0.hrMax > 0 ? $0.hrMax : nil }.max() ?? 0
    }

    /// 円形プログレスバー用の進捗値（0.0〜1.0）
    /// セッション開始から 60 分を 1 周分とする（視覚目安）
    private var elapsedProgress: Double {
        let target: TimeInterval = 60 * 60
        return min(sessionManager.elapsedTime / target, 1.0)
    }

    private var domainAccent: Color {
        switch sessionManager.activeDomain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 16) {
                    progressRing
                        .padding(.top, 4)

                    statsGrid
                        .padding(.horizontal, 12)

                    if sessionManager.activeDomain == .workout && !workRecords.isEmpty {
                        perCycleSummary
                            .padding(.horizontal, 12)
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.2))
                        .padding(.vertical, 4)

                    // 次セット設定フォーム（MainTimerView から注入）
                    formContent()
                        .padding(.horizontal, 12)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            startNextSetButton
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 上部バー: 戻るボタン + タイトル
    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("戻る")
                }
                .font(.callout)
                .foregroundColor(.white)
            }
            Spacer()
            Text("セッション進捗")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            // 左右バランス用のダミー（タイトル中央寄せ）
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("戻る")
            }
            .font(.callout)
            .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.1))
    }

    /// 次セットへ進むボタン（commitNextSetAndStart 相当を親に委譲）
    private var startNextSetButton: some View {
        Button(action: onStartNextSet) {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill").font(.system(size: 28))
                Text("次の\(sessionManager.activeDomain.workPhaseLabel)へ")
                    .font(.title3).fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(colors: [domainAccent, domainAccent.opacity(0.75)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: domainAccent.opacity(0.5), radius: 10, x: 0, y: 5)
            )
        }
    }

    // MARK: - Progress Ring
    @ViewBuilder
    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: elapsedProgress)
                .stroke(
                    LinearGradient(
                        colors: [domainAccent, domainAccent.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: elapsedProgress)
            VStack(spacing: 2) {
                Text(formatDuration(sessionManager.elapsedTime))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("経過時間")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                if elapsedProgress >= 1.0 {
                    Text("60分超")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: - Stats Grid
    @ViewBuilder
    private var statsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 10) {
            statCard(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                label: "完了セット",
                value: "\(completedWorkSets)",
                unit: "セット"
            )
            statCard(
                icon: "flame.fill",
                iconColor: .orange,
                label: sessionManager.activeDomain.workPhaseLabel,
                value: formatDuration(sessionManager.totalWorkTime),
                unit: nil
            )
            statCard(
                icon: "pause.fill",
                iconColor: .cyan,
                label: sessionManager.activeDomain.restPhaseLabel,
                value: formatDuration(sessionManager.totalRestTime),
                unit: nil
            )
            if sessionManager.activeDomain == .workout {
                statCard(
                    icon: "scalemass.fill",
                    iconColor: .yellow,
                    label: "総ボリューム",
                    value: String(format: "%.0f", totalVolume),
                    unit: sessionManager.loadUnit
                )
            } else {
                statCard(
                    icon: "number",
                    iconColor: .purple,
                    label: "サイクル",
                    value: "\(sessionManager.cycleIndex + 1)",
                    unit: nil
                )
            }
            if avgHeartRate > 0 {
                statCard(
                    icon: "heart.fill",
                    iconColor: .red,
                    label: "平均心拍",
                    value: "\(Int(avgHeartRate))",
                    unit: "bpm"
                )
            }
            if maxHeartRate > 0 {
                statCard(
                    icon: "heart.circle.fill",
                    iconColor: .pink,
                    label: "最大心拍",
                    value: "\(Int(maxHeartRate))",
                    unit: "bpm"
                )
            }
        }
    }

    @ViewBuilder
    private func statCard(icon: String, iconColor: Color, label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.12))
        )
    }

    // MARK: - Per-Cycle Summary
    @ViewBuilder
    private var perCycleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("セット内訳")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            ForEach(Array(workRecords.sorted { $0.cycleIndex < $1.cycleIndex }.enumerated()), id: \.offset) { index, record in
                HStack(spacing: 8) {
                    Text("Cycle \(record.cycleIndex + 1)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 60, alignment: .leading)
                    Text(record.name ?? "-")
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(record.reps))×\(String(format: "%.1f", record.load))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.85))
                    if record.hrAvg > 0 {
                        Label("\(Int(record.hrAvg))", systemImage: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red.opacity(0.9))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                )
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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
