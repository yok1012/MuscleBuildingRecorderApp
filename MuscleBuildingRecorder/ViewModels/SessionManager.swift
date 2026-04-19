import Foundation
import Combine
import CoreData
import WatchConnectivity
import UIKit
import UserNotifications

class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var currentPhase: WorkoutPhase = .idle
    @Published var phaseStartTime: Date?
    @Published var elapsedTimeString: String = "00:00"
    @Published var elapsedTime: TimeInterval = 0
    @Published var totalWorkTime: TimeInterval = 0
    @Published var totalRestTime: TimeInterval = 0
    @Published var currentSession: Session?
    @Published var currentSetRecord: SetRecord?
    @Published var lastCompletedSession: Session?
    @Published var cycleIndex: Int = 0
    /// Watch経由でセッションが終了された場合にtrueになるフラグ（MainTimerViewが.onChangeで監視）
    @Published var sessionEndedFromWatch: Bool = false

    @Published var selectedCategory: String = "胸"
    @Published var selectedExercise: String = "ベンチプレス"
    @Published var currentLoad: Double = 40.0
    @Published var currentReps: Double = 10.0
    @Published var currentNote: String = ""
    @Published var loadUnit: String = "kg"
    @Published var repsUnit: String = "回"

    // 休憩時間管理
    @Published var restTimeLimit: TimeInterval = 60  // 休憩時間の上限（秒）
    @Published var isRestTimeExceeded: Bool = false   // 休憩時間超過フラグ
    @Published var restTimeAlertEnabled: Bool = true  // 休憩時間アラート有効/無効

    // 心拍数自動判別
    @Published var autoPhaseDetectionEnabled: Bool = false  // 自動判別機能の有効/無効
    @Published var suggestedPhase: WorkoutPhase? = nil       // 推奨フェーズ（現在のフェーズと異なる場合に表示）
    @Published var heartRateBaseline: Double = 70            // 安静時心拍数の基準値

    // MARK: - Timer (Combine-based unified timer)
    private var timerCancellable: AnyCancellable?
    private var workTimeAccumulated: TimeInterval = 0
    private var restTimeAccumulated: TimeInterval = 0
    private var sessionStartTime: Date?

    // MARK: - Watch Authority Timer
    /// Watchがタイマーの権威ソースかどうか
    private var isWatchTimeAuthority: Bool = false
    /// Watch基準の筋トレ時間
    private var watchBaseWorkTime: TimeInterval = 0
    /// Watch基準の休憩時間
    private var watchBaseRestTime: TimeInterval = 0
    /// Watch基準値を受信した時刻
    private var watchBaseReceivedAt: Date?
    /// Watch基準値受信時のフェーズ
    private var watchBasePhase: WorkoutPhase?

    // Widget/Live Activity更新の頻度制限
    private var lastWidgetUpdateTime: Date = .distantPast
    private let widgetUpdateInterval: TimeInterval = 1.0  // 1秒間隔

    private let dataController = DataController.shared
    private let heartRateManager = HeartRateManager.shared
    private let watchConnectivity = WatchConnectivityService.shared
    private let heartRateLogManager = HeartRateLogManager.shared
    private let sensorLogManager = SensorLogManager.shared
    private let heartRateCSVLogger = HeartRateCSVLogger.shared  // 心拍数CSVログ
    private let noteLogger = WorkoutNoteLogger.shared           // タイムスタンプ付きメモログ
    private var heartRateCancellable: AnyCancellable?
    private var sessionSensorData: [[String: Any]] = []  // セッション中のセンサーデータ

    // 心拍数CSVログ補完用
    private var currentPhaseStartTimestamp: Int64 = 0

    private init() {
        loadDefaultExerciseValues()
        setupHeartRateLogging()
    }

    private func setupHeartRateLogging() {
        // HeartRateManagerからの心拍数更新を購読
        heartRateCancellable = heartRateManager.$currentHeartRate
            .sink { [weak self] heartRate in
                guard let self = self,
                      self.currentPhase != .idle,
                      heartRate > 0 else { return }

                // 心拍数ログを記録（メモリ内）
                self.heartRateLogManager.addLog(
                    heartRate: heartRate,
                    phase: self.currentPhase.rawValue.capitalized,
                    cycleIndex: self.cycleIndex
                )

                // 心拍数CSVログを記録（ファイル出力）
                self.heartRateCSVLogger.logHeartRate(heartRate)

                // 心拍数による自動フェーズ判別
                self.analyzeHeartRateForPhaseDetection(heartRate: heartRate)
            }
    }

    // MARK: - Heart Rate Auto Phase Detection
    private var lastHeartRateAnalysisTime: Date = Date()
    private let heartRateAnalysisInterval: TimeInterval = 3.0  // 3秒ごとに分析

    private func analyzeHeartRateForPhaseDetection(heartRate: Double) {
        guard autoPhaseDetectionEnabled else {
            suggestedPhase = nil
            return
        }

        // 3秒ごとに分析
        let now = Date()
        guard now.timeIntervalSince(lastHeartRateAnalysisTime) >= heartRateAnalysisInterval else {
            return
        }
        lastHeartRateAnalysisTime = now

        let slope = heartRateManager.heartRateSlope
        let relativeHR = heartRate / heartRateBaseline  // 安静時に対する比率

        // 判別ロジック:
        // - 心拍数が基準の120%以上 かつ 傾きが正 → 運動中と推定
        // - 心拍数が基準の110%以下 かつ 傾きが負 → 休憩中と推定
        let detectedPhase: WorkoutPhase?

        if relativeHR >= 1.2 && slope > 0 {
            // 心拍数が高く、さらに上昇中 → 運動中
            detectedPhase = .work
        } else if relativeHR <= 1.1 && slope < -2 {
            // 心拍数が低め、下降中 → 休憩中
            detectedPhase = .rest
        } else if relativeHR >= 1.3 {
            // 心拍数が非常に高い → 運動中（傾きに関係なく）
            detectedPhase = .work
        } else if relativeHR <= 1.05 && heartRate < heartRateBaseline + 10 {
            // 心拍数がほぼ安静時レベル → 休憩中
            detectedPhase = .rest
        } else {
            detectedPhase = nil
        }

        // 現在のフェーズと異なる場合のみ提案
        DispatchQueue.main.async {
            if let detected = detectedPhase, detected != self.currentPhase {
                self.suggestedPhase = detected
            } else {
                self.suggestedPhase = nil
            }
        }
    }

    func dismissPhaseSuggestion() {
        suggestedPhase = nil
    }

    func acceptPhaseSuggestion() {
        guard let suggested = suggestedPhase else { return }
        suggestedPhase = nil
        if suggested != currentPhase {
            togglePhase()
        }
    }

    func startSession() {
        print("SessionManager: 🎬 startSession() called")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")

        guard currentPhase == .idle else {
            print("SessionManager: ⚠️ startSession() ignored - already in \(currentPhase.rawValue) phase")
            return
        }

        print("SessionManager: ✅ Starting new session...")

        // Clear previous session result when starting new session
        lastCompletedSession = nil

        currentSession = dataController.createSession()
        currentPhase = .work
        phaseStartTime = Date()
        sessionStartTime = Date()
        cycleIndex = 0
        totalWorkTime = 0
        totalRestTime = 0
        elapsedTime = 0
        startTimer()
        setupLiveActivity()

        // 心拍数ログの記録を開始
        heartRateLogManager.startNewSession()

        // 心拍数CSVログの記録を開始
        heartRateCSVLogger.startSession()
        heartRateCSVLogger.setPhase("work", cycleIndex: cycleIndex)
        currentPhaseStartTimestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // メモログの記録を開始
        noteLogger.startSession()

        // スクリーンタイム制限を適用（機能 ON かつ認可済みのときのみ）
        if #available(iOS 16.0, *) {
            ScreenTimeManager.shared.applyShield()
        }

        // センサーデータをクリア
        sessionSensorData.removeAll()
        
        // 心拍数モニタリングを開始（Watch/iPhone自動選択）
        heartRateManager.startMonitoring()

        // Watchが利用可能な場合のみ、Watchワークアウトを開始
        if watchConnectivity.isWatchConnected {
            print("SessionManager: Watch connected - starting Watch workout")
            watchConnectivity.wakeUpWatch()
            watchConnectivity.startWatchWorkout()
        } else {
            print("SessionManager: Watch not connected - running in iPhone standalone mode")
            // iPhoneスタンドアロンモードで動作
            // 心拍数はHeartRateManagerが自動でiPhone HealthKitから取得
        }
    }

    // Watchからの時間同期付きセッション開始
    func startSessionWithTimeSync(totalWorkTime: TimeInterval, totalRestTime: TimeInterval) {
        print("SessionManager: 🎬 startSessionWithTimeSync() called")
        print("SessionManager: Synced times - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")

        guard currentPhase == .idle else {
            print("SessionManager: ⚠️ Session already active, syncing times instead")
            syncTimeFromWatch(totalWorkTime: totalWorkTime, totalRestTime: totalRestTime)
            return
        }

        // 通常のセッション開始処理
        startSession()

        // Watchからの時間データで上書き
        self.totalWorkTime = totalWorkTime
        self.totalRestTime = totalRestTime
        self.elapsedTime = totalWorkTime + totalRestTime

        print("SessionManager: ✅ Session started with Watch time sync")
    }

    // Watchからの時間データ同期
    func syncTimeFromWatch(
        totalWorkTime: TimeInterval,
        totalRestTime: TimeInterval,
        currentPhaseIdentifier: String? = nil,
        currentPhaseTime: TimeInterval? = nil,
        phaseStartDate: TimeInterval? = nil,
        completedPhaseIdentifier: String? = nil,
        completedPhaseDuration: TimeInterval? = nil,
        watchCurrentPhase: String? = nil
    ) {
        print("SessionManager: 🔄 syncTimeFromWatch() called")
        print("SessionManager: Current - Work: \(self.totalWorkTime)s, Rest: \(self.totalRestTime)s")
        print("SessionManager: Watch - Work: \(totalWorkTime)s, Rest: \(totalRestTime)s")
        if let currentPhaseIdentifier {
            print("SessionManager: Watch current phase identifier: \(currentPhaseIdentifier)")
        }
        if let completedPhaseIdentifier {
            print("SessionManager: Watch previous phase identifier: \(completedPhaseIdentifier)")
        }

        // 時間の競合解決: 経過時間が長い方を優先する
        // Watchアプリ起動時などに、一時的に0秒や古い時間が送られてくる場合があるため、
        // iPhone側が進んでいる場合はWatchからの同期を無視する
        let incomingTotalTime = totalWorkTime + totalRestTime
        let localTotalTime = self.totalWorkTime + self.totalRestTime

        // 許容する誤差（秒）- Watch起動時のゼロ値対策のため余裕を持たせる
        let tolerance: TimeInterval = 5.0

        if self.currentPhase != .idle && incomingTotalTime < (localTotalTime - tolerance) {
            print("SessionManager: ⚠️ Ignoring time sync from Watch - Incoming (\(Int(incomingTotalTime))s) < Local (\(Int(localTotalTime))s)")
            return
        }

        // Watch権威タイマー: 直接上書きではなく基準値を更新し、補間で表示
        watchBaseWorkTime = totalWorkTime
        watchBaseRestTime = totalRestTime
        watchBaseReceivedAt = Date()
        isWatchTimeAuthority = true

        // watchCurrentPhaseを記録（補間時にどのフェーズの時間を増やすか判定するため）
        if let watchPhaseStr = watchCurrentPhase, let wp = phase(from: watchPhaseStr) {
            watchBasePhase = wp
        } else if let currentPhaseId = currentPhaseIdentifier, let wp = phase(from: currentPhaseId) {
            watchBasePhase = wp
        } else {
            watchBasePhase = currentPhase != .idle ? currentPhase : nil
        }

        // completeCurrentSetRecord()用にaccumulated値をWatch値から逆算
        self.workTimeAccumulated = totalWorkTime
        self.restTimeAccumulated = totalRestTime

        // 初回同期時はセッション開始時刻も設定
        if self.sessionStartTime == nil {
            self.sessionStartTime = Date().addingTimeInterval(-(totalWorkTime + totalRestTime))
        }

        let normalizedCompletedPhase = completedPhaseIdentifier.flatMap { phase(from: $0) }
        let normalizedCurrentPhase = currentPhaseIdentifier.flatMap { phase(from: $0) }

        if let completedPhase = normalizedCompletedPhase,
           let completedDuration = completedPhaseDuration,
           completedDuration > 0 {
            switch completedPhase {
            case .work:
                self.workTimeAccumulated = max(totalWorkTime - completedDuration, 0)
            case .rest:
                self.restTimeAccumulated = max(totalRestTime - completedDuration, 0)
            case .idle:
                break
            }
            // phaseStartTime を現在時刻にリセット
            // syncTimeFromWatch が累積時間を確定済みなので、
            // 後続の completeCurrentSetRecord() で二重加算しないようにする
            self.phaseStartTime = Date()
        } else if normalizedCompletedPhase != nil {
            // フェーズ情報は届いたが時間が不明な場合は二重加算を避けるため直近時刻でリセット
            self.phaseStartTime = Date()
        } else if normalizedCompletedPhase == nil,
                  let phase = normalizedCurrentPhase,
                  let phaseDuration = currentPhaseTime {
            if phase != .idle {
                self.currentPhase = phase
            }
            self.phaseStartTime = Date().addingTimeInterval(-phaseDuration)
        }

        if let phase = normalizedCurrentPhase {
            self.currentPhase = phase
        }

        // タイムスタンプベースの正確な同期（優先）
        if let startDate = phaseStartDate, startDate > 0 {
            let start = Date(timeIntervalSince1970: startDate)
            self.phaseStartTime = start
            print("SessionManager: ⏱️ Synced phase start time from timestamp: \(start)")
        }

        // 基準値から現在の表示値を更新
        self.totalWorkTime = totalWorkTime
        self.totalRestTime = totalRestTime
        self.elapsedTime = totalWorkTime + totalRestTime

        // 表示用文字列も更新（フェーズ経過時間を正しく計算）
        updateElapsedTime()

        print("SessionManager: ✅ Times synced from Watch (authority mode)")

        // セッションやIDが欠落している場合は補完する（Watchのみで開始されたケースを考慮）
        let shouldEnsureSession = currentPhase != .idle || totalWorkTime > 0 || totalRestTime > 0
        let session = shouldEnsureSession ? ensureActiveSession(startTime: sessionStartTime) : currentSession

        // Watch側で先行して開始されたケースでセットレコードが未生成の場合のみ作成
        if currentSetRecord == nil,
           let session,
           let sessionId = session.id,
           currentPhase != .idle {
            let record = dataController.createSetRecord(
                sessionId: sessionId,
                phase: currentPhase,
                cycleIndex: cycleIndex
            )
            record.category = selectedCategory
            record.name = selectedExercise
            record.load = currentLoad
            record.reps = currentReps
            record.session = session
            currentSetRecord = record

            // Core Dataに即座に保存
            dataController.save()
        }
    }

    func togglePhase() {
        // iPhone UIからの呼び出し用（Watchに通知する）
        togglePhaseInternal(notifyWatch: true)
    }

    /// Watchからのフェーズ変更を適用（Watchには通知しない）
    /// - Parameters:
    ///   - newPhaseIdentifier: 新しいフェーズ ("work" or "rest")
    ///   - previousPhaseIdentifier: 前のフェーズ
    ///   - previousPhaseDuration: 前のフェーズの継続時間
    func applyPhaseChangeFromWatch(
        newPhaseIdentifier: String,
        previousPhaseIdentifier: String?,
        previousPhaseDuration: TimeInterval?
    ) {
        print("SessionManager: 📲 applyPhaseChangeFromWatch() - newPhase: \(newPhaseIdentifier)")

        guard let newPhase = phase(from: newPhaseIdentifier), newPhase != .idle else {
            print("SessionManager: ⚠️ Invalid phase identifier: \(newPhaseIdentifier)")
            return
        }

        // idleの場合はセッション開始
        if currentPhase == .idle {
            print("SessionManager: 🚀 Starting new session from Watch command")
            startSession()
            // セッション開始後、必要に応じてフェーズを設定
            if newPhase != .work {
                applyPhaseInternal(newPhase: newPhase, notifyWatch: false)
            }
            return
        }

        // 既に同じフェーズの場合は何もしない（重複処理防止）
        if currentPhase == newPhase {
            print("SessionManager: ℹ️ Already in phase \(newPhaseIdentifier), skipping")
            return
        }

        applyPhaseInternal(newPhase: newPhase, notifyWatch: false)
    }

    /// フェーズ変更の内部実装
    /// - Parameters:
    ///   - newPhase: 新しいフェーズ
    ///   - notifyWatch: Watchに通知するかどうか（iPhone UIからの操作時はtrue、Watchからの操作時はfalse）
    private func applyPhaseInternal(newPhase: WorkoutPhase, notifyWatch: Bool) {
        let previousPhase = currentPhase
        let now = Date()
        let phaseEndTimestamp = Int64(now.timeIntervalSince1970 * 1000)
        let completedPhaseDuration: TimeInterval
        if let startTime = phaseStartTime {
            completedPhaseDuration = max(now.timeIntervalSince(startTime), 0)
        } else {
            completedPhaseDuration = 0
        }

        // 心拍数CSVログの補完（前のフェーズのデータに種目情報を追記）
        if currentPhaseStartTimestamp > 0 {
            heartRateCSVLogger.supplementPhaseData(
                phaseStartTimestamp: currentPhaseStartTimestamp,
                phaseEndTimestamp: phaseEndTimestamp,
                category: selectedCategory,
                exercise: selectedExercise,
                reps: currentReps,
                load: currentLoad,
                note: currentNote
            )
        }

        completeCurrentSetRecord()

        guard let session = ensureActiveSession(startTime: sessionStartTime),
              let sessionId = session.id else {
            print("SessionManager: ⚠️ applyPhaseInternal() aborted - active session unavailable")
            return
        }

        // サイクルインデックスの更新（rest→workの遷移時）
        if previousPhase == .rest && newPhase == .work {
            cycleIndex += 1
        }

        currentPhase = newPhase
        phaseStartTime = now

        // Watch権威タイマーの基準値を更新（フェーズ遷移時にリセット）
        if isWatchTimeAuthority {
            watchBaseWorkTime = totalWorkTime
            watchBaseRestTime = totalRestTime
            watchBaseReceivedAt = now
            watchBasePhase = newPhase
        }

        // 心拍数CSVログの新しいフェーズを開始
        currentPhaseStartTimestamp = Int64(now.timeIntervalSince1970 * 1000)
        heartRateCSVLogger.setPhase(newPhase.rawValue, cycleIndex: cycleIndex)

        // 休憩時間アラートをリセット
        resetRestTimeAlert()

        // 新しいフェーズ開始時は表示を00:00にリセット
        // （タイマーが次のtickでphaseStartTimeから計算するまでの間、総時間が一瞬表示されるのを防ぐ）
        elapsedTimeString = "00:00"

        if let sessionStart = sessionStartTime {
            // 総セッション時間は更新（統計用）
            elapsedTime = now.timeIntervalSince(sessionStart)
        }

        // Watchに通知（iPhone UIからの操作時のみ）
        if notifyWatch {
            watchConnectivity.sendPhaseChange(
                phase: newPhase.rawValue,
                cycleIndex: cycleIndex,
                totalWorkTime: totalWorkTime,
                totalRestTime: totalRestTime,
                elapsedTime: elapsedTime,
                currentPhaseTime: 0,
                phaseStartDate: phaseStartTime,
                previousPhase: previousPhase.rawValue,
                previousPhaseDuration: completedPhaseDuration
            )
        }

        let record = dataController.createSetRecord(
            sessionId: sessionId,
            phase: newPhase,
            cycleIndex: cycleIndex
        )
        record.category = selectedCategory
        record.name = selectedExercise
        record.load = currentLoad
        record.reps = currentReps
        record.note = currentNote
        record.session = currentSession
        currentSetRecord = record

        // Core Dataに即座に保存
        dataController.save()

        // 休憩フェーズに入った時は通知をスケジュール
        if newPhase == .rest {
            scheduleRestNotifications()
        } else {
            // ワークフェーズに入った時は通知をキャンセル
            cancelRestNotifications()
        }

        // スクリーンタイム制限の一時解除／再ロック（Pro 機能）
        if #available(iOS 16.0, *) {
            let manager = ScreenTimeManager.shared
            if newPhase == .rest {
                // 休憩入り: Pro なら N 秒解除ウィンドウを開始
                manager.startRestPhaseUnlock(isPro: ProUserManager.shared.isPro)
            } else if newPhase == .work {
                // 筋トレ復帰: 解除ウィンドウをキャンセルして即再ロック
                manager.cancelRestUnlockAndReapply()
            }
        }

        // Widget/Live Activityを強制更新（フェーズ変更時は即座に更新）
        WidgetStateStore.shared.forceWidgetUpdate()
        syncToWidgetState()
        setupLiveActivity()

        print("SessionManager: ✅ Phase changed to \(newPhase.rawValue), notifyWatch: \(notifyWatch)")
    }

    /// iPhone UIからのトグル操作
    private func togglePhaseInternal(notifyWatch: Bool) {
        print("SessionManager: 🔄 togglePhaseInternal() called, notifyWatch: \(notifyWatch)")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")

        guard currentPhase != .idle else {
            print("SessionManager: 🚀 togglePhase() starting new session from idle")
            startSession()
            return
        }

        let newPhase: WorkoutPhase = currentPhase == .work ? .rest : .work
        applyPhaseInternal(newPhase: newPhase, notifyWatch: notifyWatch)
    }

    func saveCurrentCycle() {
        guard let record = currentSetRecord, currentPhase == .rest else { return }

        completeCurrentSetRecord()
        dataController.save()

        currentNote = ""
    }

    func endSession() {
        print("SessionManager: 🛑 endSession() called")
        print("SessionManager: Current phase: \(currentPhase.rawValue)")

        stopTimer()
        print("SessionManager: Timer stopped")

        // 最後のフェーズの心拍数CSVログを補完
        let now = Date()
        let phaseEndTimestamp = Int64(now.timeIntervalSince1970 * 1000)
        if currentPhaseStartTimestamp > 0 {
            heartRateCSVLogger.supplementPhaseData(
                phaseStartTimestamp: currentPhaseStartTimestamp,
                phaseEndTimestamp: phaseEndTimestamp,
                category: selectedCategory,
                exercise: selectedExercise,
                reps: currentReps,
                load: currentLoad,
                note: currentNote
            )
        }

        // 心拍数CSVログを終了
        heartRateCSVLogger.endSession()
        currentPhaseStartTimestamp = 0

        // メモログを終了
        noteLogger.endSession()

        // スクリーンタイム制限を解除
        if #available(iOS 16.0, *) {
            ScreenTimeManager.shared.removeShield()
        }

        if currentSetRecord != nil {
            completeCurrentSetRecord()
        }

        if let session = currentSession {
            session.endedAt = now
            session.totalWorkSec = Int32(totalWorkTime)
            session.totalRestSec = Int32(totalRestTime)
            session.totalVolume = calculateTotalVolume()

            // 心拍数ログを保存
            _ = heartRateLogManager.currentSessionLogs

            dataController.save()

            // セッションデータを保持（リザルト画面で表示するため）
            lastCompletedSession = session
        }

        // 心拍数モニタリングを停止
        heartRateManager.stopMonitoring()

        // Watchが接続されている場合のみ、Watchワークアウト終了を通知
        if watchConnectivity.isWatchConnected {
            watchConnectivity.stopWatchWorkout()
        }

        // iPhone側のWatch状態をリセット（前回セッションの時間表示を防ぐ）
        watchConnectivity.resetWatchState()

        // Watch権威タイマー状態をリセット
        isWatchTimeAuthority = false
        watchBaseReceivedAt = nil

        // 休憩通知をキャンセル
        cancelRestNotifications()

        // Widget/Live Activityの状態をクリア
        WidgetStateStore.shared.clearWorkoutState()
        LiveActivityManager.shared.endLiveActivity()

        // セッションを完全にリセット（時間データは lastCompletedSession に保存済み）
        resetSession()
    }

    private func completeCurrentSetRecord() {
        guard let record = currentSetRecord else { return }

        record.endAt = Date()
        record.note = currentNote

        let hrStats = heartRateManager.getHeartRateStats()
        record.hrAvg = hrStats.avg
        record.hrMax = hrStats.max
        record.hrMin = hrStats.min
        record.hrSlopeAvg = heartRateManager.heartRateSlope

        if let startTime = phaseStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if currentPhase == .work {
                workTimeAccumulated += elapsed
                totalWorkTime = workTimeAccumulated
            } else {
                restTimeAccumulated += elapsed
                totalRestTime = restTimeAccumulated
            }
        }

        dataController.save()
    }

    // MARK: - Unified Timer (Combine-based)

    /// Combineベースの統一タイマーを開始
    /// - 1秒間隔でtimerTickを実行
    /// - メモリリーク防止のためweak selfを使用
    private func startTimer() {
        // 既存のタイマーがあればキャンセル
        timerCancellable?.cancel()

        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTimerTick()
            }
    }

    /// タイマーを停止
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// 統一タイマーのtick処理
    /// - 時間更新、休憩時間チェック、Widget更新を一括管理
    private func handleTimerTick() {
        guard currentPhase != .idle else { return }

        // 1. 経過時間を更新
        updateElapsedTime()

        // 2. Widget/Live Activity更新（頻度制限付き）
        updateWidgetIfNeeded()
    }

    /// 経過時間の更新処理
    private func updateElapsedTime() {
        guard let startTime = phaseStartTime else {
            elapsedTimeString = "00:00"
            return
        }

        let phaseElapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(phaseElapsed) / 60
        let seconds = Int(phaseElapsed) % 60
        elapsedTimeString = String(format: "%02d:%02d", minutes, seconds)

        if isWatchTimeAuthority, let receivedAt = watchBaseReceivedAt {
            // Watch権威モード: Watch基準値からの補間で計算（直接上書きによるジャンプを防ぐ）
            let timeSinceSync = max(Date().timeIntervalSince(receivedAt), 0)
            let activePhase = watchBasePhase ?? currentPhase

            if activePhase == .work {
                totalWorkTime = watchBaseWorkTime + timeSinceSync
                totalRestTime = watchBaseRestTime
            } else if activePhase == .rest {
                totalWorkTime = watchBaseWorkTime
                totalRestTime = watchBaseRestTime + timeSinceSync

                // 休憩時間超過チェック
                checkRestTimeExceeded(phaseElapsed: phaseElapsed)
            }
        } else {
            // iPhoneスタンドアロンモード: 既存のローカルタイマーロジック
            if currentPhase == .work {
                totalWorkTime = workTimeAccumulated + phaseElapsed
            } else if currentPhase == .rest {
                totalRestTime = restTimeAccumulated + phaseElapsed

                // 休憩時間超過チェック
                checkRestTimeExceeded(phaseElapsed: phaseElapsed)
            }
        }

        // 総経過時間は常にwork+restの合計として計算（統一）
        elapsedTime = totalWorkTime + totalRestTime
    }

    /// Widget/Live Activityの更新（頻度制限付き）
    private func updateWidgetIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastWidgetUpdateTime) >= widgetUpdateInterval else {
            return
        }
        lastWidgetUpdateTime = now

        // Widget/Live Activityに状態を同期
        syncToWidgetState()

        // Live Activityも更新
        setupLiveActivity()
    }

    // MARK: - Rest Time Alert
    private var hasTriggeredRestAlert: Bool = false

    private func checkRestTimeExceeded(phaseElapsed: TimeInterval) {
        guard restTimeAlertEnabled else { return }

        if phaseElapsed >= restTimeLimit && !hasTriggeredRestAlert {
            hasTriggeredRestAlert = true
            isRestTimeExceeded = true
            triggerRestTimeAlert()
        }
    }

    private func triggerRestTimeAlert() {
        // バイブレーション
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // ローカル通知
        let content = UNMutableNotificationContent()
        content.title = "休憩時間超過"
        content.body = "設定した休憩時間（\(Int(restTimeLimit))秒）を超えました。次のセットを始めましょう！"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "restTimeExceeded",
            content: content,
            trigger: nil  // 即時
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule rest time notification: \(error)")
            }
        }
    }

    func resetRestTimeAlert() {
        hasTriggeredRestAlert = false
        isRestTimeExceeded = false
    }

    private func resetSession() {
        currentPhase = .idle
        phaseStartTime = nil
        sessionStartTime = nil
        elapsedTimeString = "00:00"
        elapsedTime = 0
        totalWorkTime = 0
        totalRestTime = 0
        currentSession = nil
        currentSetRecord = nil
        cycleIndex = 0
        workTimeAccumulated = 0
        restTimeAccumulated = 0

        // Watch権威タイマーをリセット
        isWatchTimeAuthority = false
        watchBaseWorkTime = 0
        watchBaseRestTime = 0
        watchBaseReceivedAt = nil
        watchBasePhase = nil

        // メモリクリーンアップ
        sessionSensorData.removeAll()
        heartRateLogManager.clearLogs()
    }

    @discardableResult
    private func ensureActiveSession(startTime: Date? = nil) -> Session? {
        if currentSession == nil {
            let resolvedStart = startTime ?? sessionStartTime ?? Date()
            sessionStartTime = sessionStartTime ?? resolvedStart

            let session = dataController.createSession()
            session.startedAt = resolvedStart
            currentSession = session
        }

        if let session = currentSession, session.id == nil {
            session.id = UUID()
        }

        if timerCancellable == nil, currentPhase != .idle {
            startTimer()
        }

        return currentSession
    }

    private func calculateTotalVolume() -> Double {
        guard let session = currentSession,
              let records = session.setRecords?.allObjects as? [SetRecord] else { return 0 }

        return records.reduce(0) { $0 + ($1.load * $1.reps) }
    }

    private func phase(from identifier: String) -> WorkoutPhase? {
        switch identifier.lowercased() {
        case "work", "筋トレ":
            return .work
        case "rest", "休憩":
            return .rest
        case "idle", "待機中":
            return .idle
        default:
            return WorkoutPhase(rawValue: identifier.capitalized)
        }
    }

    func loadDefaultExerciseValues() {
        let request = NSFetchRequest<ExerciseMaster>(entityName: "ExerciseMaster")
        request.predicate = NSPredicate(
            format: "category == %@ AND name == %@",
            selectedCategory,
            selectedExercise
        )

        do {
            let exercises = try dataController.container.viewContext.fetch(request)
            if let exercise = exercises.first {
                currentLoad = exercise.defaultLoad
                currentReps = exercise.defaultReps
                loadUnit = exercise.loadUnit ?? "kg"
                repsUnit = exercise.repsUnit ?? "回"
            }
        } catch {
            print("Failed to load exercise defaults: \(error)")
        }
    }

    func getAvailableCategories() -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "ExerciseMaster")
        request.propertiesToFetch = ["category"]
        request.returnsDistinctResults = true
        request.resultType = .dictionaryResultType

        do {
            let results = try dataController.container.viewContext.fetch(request)
            return results.compactMap { $0["category"] as? String }.sorted()
        } catch {
            print("Failed to fetch categories: \(error)")
            return []
        }
    }

    func getExercises(for category: String) -> [String] {
        let request = NSFetchRequest<ExerciseMaster>(entityName: "ExerciseMaster")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let exercises = try dataController.container.viewContext.fetch(request)
            return exercises.compactMap { $0.name }
        } catch {
            print("Failed to fetch exercises: \(error)")
            return []
        }
    }

    // センサーデータを取得（セッション期間中のデータ）
    func getSensorDataForCurrentSession() -> String {
        guard let startTime = sessionStartTime else { return "[]" }

        // SensorLogManagerから現在の日付のデータを取得
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        // 加速度データファイルのパスを取得
        let accelUrl = sensorLogManager.logDirectory.appendingPathComponent("accelerometer_\(dateString).csv")
        let gyroUrl = sensorLogManager.logDirectory.appendingPathComponent("gyroscope_\(dateString).csv")

        var sensorData: [[String: Any]] = []

        // 加速度データを読み込み
        if FileManager.default.fileExists(atPath: accelUrl.path) {
            do {
                let csvContent = try String(contentsOf: accelUrl, encoding: .utf8)
                let lines = csvContent.components(separatedBy: .newlines)

                for (index, line) in lines.enumerated() {
                    if index == 0 || line.isEmpty { continue } // ヘッダーをスキップ

                    let components = line.components(separatedBy: ",")
                    if components.count >= 4 {
                        if let timestamp = Int64(components[0]),
                           let ax = Double(components[1]),
                           let ay = Double(components[2]),
                           let az = Double(components[3]) {

                            let sampleTime = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)

                            // セッション期間中のデータのみ
                            if sampleTime >= startTime {
                                sensorData.append([
                                    "timestamp": timestamp,
                                    "accelX": ax,
                                    "accelY": ay,
                                    "accelZ": az
                                ])
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read accelerometer data: \(error)")
            }
        }

        // ジャイロデータを追加（同じtimestampのデータに追加）
        if FileManager.default.fileExists(atPath: gyroUrl.path) {
            do {
                let csvContent = try String(contentsOf: gyroUrl, encoding: .utf8)
                let lines = csvContent.components(separatedBy: .newlines)

                for (index, line) in lines.enumerated() {
                    if index == 0 || line.isEmpty { continue }

                    let components = line.components(separatedBy: ",")
                    if components.count >= 4 {
                        if let timestamp = Int64(components[0]),
                           let gx = Double(components[1]),
                           let gy = Double(components[2]),
                           let gz = Double(components[3]) {

                            // 既存のデータに追加
                            if let index = sensorData.firstIndex(where: { $0["timestamp"] as? Int64 == timestamp }) {
                                sensorData[index]["gyroX"] = gx
                                sensorData[index]["gyroY"] = gy
                                sensorData[index]["gyroZ"] = gz
                            }
                        }
                    }
                }
            } catch {
                print("Failed to read gyroscope data: \(error)")
            }
        }

        // JSON文字列に変換
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sensorData, options: [])
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            print("Failed to serialize sensor data: \(error)")
            return "[]"
        }
    }

    // MARK: - Quick Note Entry

    /// 筋トレ中・休憩中の任意タイミングでメモを残す。
    /// - メモ自体は `WorkoutNoteLogger` で時系列保存（メモリ + notes_yyyyMMdd.csv）
    /// - 同タイミングの心拍数行として `HeartRateCSVLogger` にも記録し、心拍データと結合可能にする
    /// - `currentSetRecord.note` にも「改行区切りで追記」するので Core Data の履歴にも反映
    /// - Parameter text: 入力されたメモ本文（空や空白のみは無視）
    /// - Returns: 記録された Entry（空入力時は nil）
    @discardableResult
    func addQuickNote(_ text: String) -> WorkoutNoteEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard currentPhase != .idle else {
            print("SessionManager: ⚠️ addQuickNote ignored - session is idle")
            return nil
        }

        let hr = heartRateManager.currentHeartRate

        // 1. 時系列メモログへ
        let entry = noteLogger.addNote(
            text: trimmed,
            phase: currentPhase.rawValue,
            cycleIndex: cycleIndex,
            heartRate: hr
        )

        // 2. 心拍数CSVにも note 付き行として書き込み（行単位で心拍データと結合できる）
        heartRateCSVLogger.recordInstantNote(text: trimmed, heartRate: hr)

        // 3. 現在の SetRecord.note にも追記（既存の履歴UI向け、改行区切り）
        if let record = currentSetRecord {
            let existing = (record.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                record.note = trimmed
            } else {
                record.note = existing + "\n" + trimmed
            }
            // currentNote も追記して次のフェーズ遷移時の補完に反映
            currentNote = record.note ?? trimmed
            dataController.save()
        } else {
            // SetRecord がまだ無い場合（異常系）は少なくとも currentNote に保持
            let existing = currentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            currentNote = existing.isEmpty ? trimmed : existing + "\n" + trimmed
        }

        print("SessionManager: 📝 Note added - phase: \(currentPhase.rawValue), hr: \(Int(hr)), text: \(trimmed)")
        return entry
    }

    // MARK: - Session Persistence (タスクキル対応)

    /// 復元可能なセッション状態があるかチェック
    @Published var hasPendingSessionRestore: Bool = false
    @Published var pendingRestoreState: SessionPersistenceState?

    /// 現在のセッション状態を永続化
    func saveSessionState() {
        guard currentPhase != .idle else {
            // idleの場合は保存済み状態をクリア
            clearSavedSessionState()
            return
        }

        let state = SessionPersistenceState(
            sessionId: currentSession?.id?.uuidString,
            phase: currentPhase.rawValue,
            totalWorkTime: totalWorkTime,
            totalRestTime: totalRestTime,
            phaseStartTime: phaseStartTime,
            sessionStartTime: sessionStartTime,
            cycleIndex: cycleIndex,
            selectedCategory: selectedCategory,
            selectedExercise: selectedExercise,
            currentLoad: currentLoad,
            currentReps: currentReps,
            savedAt: Date()
        )

        guard let userDefaults = AppGroupConfig.sharedUserDefaults else {
            print("SessionManager: ❌ Failed to get App Group UserDefaults")
            return
        }

        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: WidgetStateKeys.sessionPersistenceState)
            userDefaults.synchronize()
            print("SessionManager: 💾 Session state saved - phase: \(state.phase), work: \(Int(state.totalWorkTime))s, rest: \(Int(state.totalRestTime))s")
        } catch {
            print("SessionManager: ❌ Failed to save session state: \(error)")
        }
    }

    /// 保存されたセッション状態をクリア
    func clearSavedSessionState() {
        guard let userDefaults = AppGroupConfig.sharedUserDefaults else { return }
        userDefaults.removeObject(forKey: WidgetStateKeys.sessionPersistenceState)
        userDefaults.synchronize()
        hasPendingSessionRestore = false
        pendingRestoreState = nil
        print("SessionManager: 🗑️ Saved session state cleared")
    }

    /// 保存されたセッション状態を読み込み（起動時に呼び出し）
    func loadSavedSessionState() {
        guard let userDefaults = AppGroupConfig.sharedUserDefaults,
              let data = userDefaults.data(forKey: WidgetStateKeys.sessionPersistenceState) else {
            // 保存状態がない場合、不整合を防ぐためWidgetStateもクリア
            hasPendingSessionRestore = false
            pendingRestoreState = nil
            cleanupInconsistentState()
            return
        }

        do {
            let state = try JSONDecoder().decode(SessionPersistenceState.self, from: data)
            if state.isValidForRestore {
                pendingRestoreState = state
                hasPendingSessionRestore = true
                print("SessionManager: 📂 Found restorable session - phase: \(state.phase), saved \(state.timeSinceSavedString)")
            } else {
                // 無効な状態（古すぎるorアイドル）はクリア
                clearSavedSessionState()
                cleanupInconsistentState()
            }
        } catch {
            print("SessionManager: ❌ Failed to load saved session state: \(error)")
            clearSavedSessionState()
            cleanupInconsistentState()
        }
    }

    /// 不整合状態をクリーンアップ（起動時に呼び出し）
    private func cleanupInconsistentState() {
        // 現在idleで、保存状態もない場合は完全リセット
        if currentPhase == .idle {
            // Widget状態をクリア
            WidgetStateStore.shared.clearWorkoutState()

            // SessionManagerの時間関連プロパティもリセット（残留データ防止）
            resetSession()

            print("SessionManager: 🧹 Cleaned up inconsistent state - all properties reset")
        }
    }

    /// 保存されたセッションを復元
    func restoreSession() {
        guard let state = pendingRestoreState, state.isValidForRestore else {
            print("SessionManager: ⚠️ No valid session to restore")
            clearSavedSessionState()
            return
        }

        print("SessionManager: 🔄 Restoring session...")

        // セッション/SetRecordの復元（Core Dataから検索or新規作成）
        if let sessionIdString = state.sessionId,
           let sessionId = UUID(uuidString: sessionIdString) {
            // 既存セッションを検索
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
            request.fetchLimit = 1

            if let existingSession = try? dataController.container.viewContext.fetch(request).first {
                currentSession = existingSession
                print("SessionManager: ✅ Restored existing session from Core Data")
            } else {
                // セッションが見つからない場合は新規作成
                let session = dataController.createSession()
                session.startedAt = state.sessionStartTime ?? Date()
                currentSession = session
                print("SessionManager: ✅ Created new session (original not found)")
            }
        } else {
            // sessionIdがない場合は新規作成
            let session = dataController.createSession()
            session.startedAt = state.sessionStartTime ?? Date()
            currentSession = session
            print("SessionManager: ✅ Created new session for restore")
        }

        // 状態を復元
        selectedCategory = state.selectedCategory
        selectedExercise = state.selectedExercise
        currentLoad = state.currentLoad
        currentReps = state.currentReps
        cycleIndex = state.cycleIndex

        // 時間を復元（保存からの経過時間を加算）
        let elapsedSinceSave = state.timeSinceSaved
        let restoredPhase = WorkoutPhase(rawValue: state.phase) ?? .work

        if restoredPhase == .work {
            totalWorkTime = state.totalWorkTime + elapsedSinceSave
            totalRestTime = state.totalRestTime
        } else if restoredPhase == .rest {
            totalWorkTime = state.totalWorkTime
            totalRestTime = state.totalRestTime + elapsedSinceSave
        }

        workTimeAccumulated = totalWorkTime
        restTimeAccumulated = totalRestTime
        sessionStartTime = state.sessionStartTime
        phaseStartTime = Date()  // フェーズは今から再開
        currentPhase = restoredPhase

        // タイマー開始
        startTimer()

        // 新しいSetRecordを作成
        guard let session = currentSession, let sessionId = session.id else {
            print("SessionManager: ❌ Failed to get session for SetRecord")
            return
        }

        let record = dataController.createSetRecord(
            sessionId: sessionId,
            phase: currentPhase,
            cycleIndex: cycleIndex
        )
        // 復元時の種目情報を設定
        record.category = selectedCategory
        record.name = selectedExercise
        record.load = currentLoad
        record.reps = currentReps
        currentSetRecord = record

        // Widgetを更新
        syncToWidgetState()

        // 保存状態をクリア
        clearSavedSessionState()

        print("SessionManager: ✅ Session restored - phase: \(currentPhase.rawValue), totalWork: \(Int(totalWorkTime))s, totalRest: \(Int(totalRestTime))s")
    }

    /// セッション復元をスキップして状態をクリア
    func skipSessionRestore() {
        print("SessionManager: ⏭️ Session restore skipped by user")

        // 未完了のセッションがあればマーク
        if let state = pendingRestoreState,
           let sessionIdString = state.sessionId,
           let sessionId = UUID(uuidString: sessionIdString) {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId as CVarArg)
            request.fetchLimit = 1

            if let existingSession = try? dataController.container.viewContext.fetch(request).first {
                // 中断セッションとして終了時刻を記録
                existingSession.endedAt = Date()
                existingSession.totalWorkSec = Int32(state.totalWorkTime)
                existingSession.totalRestSec = Int32(state.totalRestTime)
                dataController.save()
                print("SessionManager: ✅ Marked interrupted session as ended")
            }
        }

        clearSavedSessionState()
        WidgetStateStore.shared.clearWorkoutState()

        // SessionManagerの状態を完全にリセット（重要！）
        resetSession()
        print("SessionManager: ✅ Session state fully reset")
    }
}
