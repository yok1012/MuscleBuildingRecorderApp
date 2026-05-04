//
//  PresetRunner.swift
//  MuscleBuildingRecorder
//
//  プリセット実行ランナー。SessionManager と協調して、
//  ステップ・セット進行を追跡。autoAdvanceEnabled が true の場合は
//  workSeconds / restSeconds 経過で自動的にフェーズ遷移し、
//  全ステップ終了でセッション自動終了する。
//
//  自動進行 OFF でも、ユーザーが手動で rest→work に切り替えると
//  セット数のカウントアップ・ステップ自動遷移は行う（種目が自動切替）。
//

import Foundation
import Combine

@MainActor
final class PresetRunner: ObservableObject {
    static let shared = PresetRunner()

    @Published private(set) var activePreset: WorkoutPreset?
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var currentSetInStep: Int = 1
    @Published var autoAdvanceEnabled: Bool = false {
        didSet {
            guard isRunning, oldValue != autoAdvanceEnabled else { return }
            if autoAdvanceEnabled {
                startThresholdTimer()
            } else {
                thresholdTimer?.cancel()
                thresholdTimer = nil
            }
        }
    }

    private var thresholdTimer: AnyCancellable?
    private var phaseSubscription: AnyCancellable?
    private var lastObservedPhase: WorkoutPhase = .idle

    private init() {}

    var isRunning: Bool { activePreset != nil }

    var currentStep: WorkoutPresetStep? {
        guard let preset = activePreset,
              currentStepIndex >= 0,
              currentStepIndex < preset.steps.count else { return nil }
        return preset.steps[currentStepIndex]
    }

    var totalStepCount: Int { activePreset?.steps.count ?? 0 }

    /// 進行表示用テキスト（例: "ステップ 1/3 ・ セット 2/4"）
    var progressText: String {
        guard let step = currentStep else { return "" }
        return "ステップ \(currentStepIndex + 1)/\(totalStepCount) ・ セット \(currentSetInStep)/\(step.setCount)"
    }

    /// 次のステップ。最終ステップなら nil。
    var nextStep: WorkoutPresetStep? {
        guard let preset = activePreset,
              currentStepIndex + 1 < preset.steps.count else { return nil }
        return preset.steps[currentStepIndex + 1]
    }

    /// 最終ステップかどうか（次の種目が存在しない）
    var isOnLastStep: Bool {
        guard let preset = activePreset else { return false }
        return currentStepIndex >= preset.steps.count - 1
    }

    /// 次のフェーズ（work↔rest）に切り替わるまでの残り秒数。
    /// - work 中: 「休憩まで」の残り秒数
    /// - rest 中: 「筋トレまで」の残り秒数
    /// - 自動進行 OFF でも、設定値ベースの予測として表示する
    func secondsUntilPhaseChange(now: Date = Date()) -> Int? {
        guard activePreset != nil, let step = currentStep else { return nil }
        let sm = SessionManager.shared
        guard sm.currentPhase != .idle, let phaseStart = sm.phaseStartTime else { return nil }

        let phaseElapsed = now.timeIntervalSince(phaseStart)
        let phaseDuration: Double
        switch sm.currentPhase {
        case .work: phaseDuration = Double(step.workSeconds)
        case .rest: phaseDuration = Double(step.restSeconds)
        case .idle: return nil
        }
        return Int(ceil(max(phaseDuration - phaseElapsed, 0)))
    }

    /// 現在のステップが終了するまでの残り秒数（次の種目／セッション終了までの推定値）。
    /// - 計算式: 残りフェーズ時間 + 残りセット分 (work + rest)
    /// - 自動進行 OFF でも、設定値ベースの予測として表示する
    func secondsUntilStepEnd(now: Date = Date()) -> Int? {
        guard activePreset != nil, let step = currentStep else { return nil }
        let sm = SessionManager.shared
        guard sm.currentPhase != .idle, let phaseStart = sm.phaseStartTime else { return nil }

        let phaseElapsed = now.timeIntervalSince(phaseStart)
        // 現在のセット以降に残る完全セット数（現在のセット自体は含めない）
        let remainingSetsAfterCurrent = max(step.setCount - currentSetInStep, 0)
        let stepCycleSeconds = Double(step.workSeconds + step.restSeconds)

        let remaining: Double
        switch sm.currentPhase {
        case .work:
            let workRemaining = max(Double(step.workSeconds) - phaseElapsed, 0)
            remaining = workRemaining
                + Double(step.restSeconds)
                + Double(remainingSetsAfterCurrent) * stepCycleSeconds
        case .rest:
            let restRemaining = max(Double(step.restSeconds) - phaseElapsed, 0)
            remaining = restRemaining
                + Double(remainingSetsAfterCurrent) * stepCycleSeconds
        case .idle:
            return nil
        }
        return Int(ceil(remaining))
    }

    // MARK: - Lifecycle

    /// プリセット実行開始
    /// - Parameter forceReplaceActiveSession: true の場合、進行中のセッションがあれば終了して上書き起動
    func start(preset: WorkoutPreset, autoAdvance: Bool, forceReplaceActiveSession: Bool = false) {
        guard !preset.steps.isEmpty else {
            print("PresetRunner: ⚠️ preset has no steps, ignored")
            return
        }

        // 既存ランナーが動いていれば一度クリーンに
        if isRunning {
            stop()
        }

        let sm = SessionManager.shared
        if sm.currentPhase != .idle {
            if forceReplaceActiveSession {
                sm.endSession()
            } else {
                print("PresetRunner: ⚠️ session not idle, abort (currentPhase=\(sm.currentPhase.rawValue))")
                return
            }
        }

        activePreset = preset
        autoAdvanceEnabled = autoAdvance
        currentStepIndex = 0
        currentSetInStep = 1
        lastObservedPhase = .idle

        loadCurrentStepIntoSession()

        if sm.currentPhase == .idle {
            sm.startSession()
        }

        subscribeToPhaseChanges()
        if autoAdvance {
            startThresholdTimer()
        }
        print("PresetRunner: ▶️ started '\(preset.title)' (\(preset.steps.count) steps, autoAdvance: \(autoAdvance))")
    }

    /// プリセット実行を終了
    func stop() {
        thresholdTimer?.cancel()
        thresholdTimer = nil
        phaseSubscription?.cancel()
        phaseSubscription = nil
        activePreset = nil
        currentStepIndex = 0
        currentSetInStep = 1
        autoAdvanceEnabled = false
        lastObservedPhase = .idle
        print("PresetRunner: ⏹️ stopped")
    }

    // MARK: - Step loading

    private func loadCurrentStepIntoSession() {
        guard let step = currentStep else { return }
        let sm = SessionManager.shared
        sm.selectedCategory = step.category
        sm.selectedExercise = step.exerciseName
        sm.restTimeLimit = TimeInterval(step.restSeconds)
        // ExerciseMaster からデフォルト負荷・回数を取得
        sm.loadDefaultExerciseValues()
        // プリセット側で指定があれば上書き
        if let load = step.defaultLoad { sm.currentLoad = load }
        if let reps = step.defaultReps { sm.currentReps = reps }
    }

    // MARK: - Phase subscription（常時 ON）

    private func subscribeToPhaseChanges() {
        phaseSubscription?.cancel()
        lastObservedPhase = SessionManager.shared.currentPhase
        phaseSubscription = SessionManager.shared.$currentPhase
            .removeDuplicates()
            .sink { [weak self] newPhase in
                self?.handlePhaseChange(to: newPhase)
            }
    }

    private func handlePhaseChange(to phase: WorkoutPhase) {
        let previous = lastObservedPhase
        lastObservedPhase = phase

        if phase == .idle {
            // セッションが外部要因で終了した
            stop()
            return
        }

        // rest → work 遷移時にカウンタを進める（自動でも手動でも）
        if previous == .rest && phase == .work {
            advanceCounters()
        }
    }

    private func advanceCounters() {
        guard let preset = activePreset, let step = currentStep else { return }
        if currentSetInStep < step.setCount {
            currentSetInStep += 1
        } else if currentStepIndex < preset.steps.count - 1 {
            currentStepIndex += 1
            currentSetInStep = 1
            loadCurrentStepIntoSession()
        }
        // 全ステップ終了済みでさらに work が始まった場合はカウンタ据え置き
    }

    // MARK: - 自動進行タイマー

    private func startThresholdTimer() {
        thresholdTimer?.cancel()
        thresholdTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.autoAdvanceTick()
            }
    }

    private func autoAdvanceTick() {
        guard autoAdvanceEnabled, activePreset != nil, let step = currentStep else { return }
        let sm = SessionManager.shared
        guard let phaseStart = sm.phaseStartTime else { return }
        let elapsed = Date().timeIntervalSince(phaseStart)

        switch sm.currentPhase {
        case .work:
            if elapsed >= TimeInterval(step.workSeconds) {
                sm.togglePhase()  // → rest
            }
        case .rest:
            if elapsed >= TimeInterval(step.restSeconds) {
                if isOnLastSetOfLastStep() {
                    sm.endSession()
                    // 終了は phase=.idle 通知で stop() される
                } else {
                    sm.togglePhase()  // → work（subscription でカウンタ進行）
                }
            }
        case .idle:
            break
        }
    }

    private func isOnLastSetOfLastStep() -> Bool {
        guard let preset = activePreset, let step = currentStep else { return false }
        return currentStepIndex == preset.steps.count - 1
            && currentSetInStep >= step.setCount
    }
}
