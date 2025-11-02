import Foundation
import Combine
import HealthKit
import CoreMotion
import WatchConnectivity

// 長期間バックグラウンド記録マネージャー（HKWorkoutSessionを利用）
class BackgroundSensorRecorder: NSObject, ObservableObject {
    static let shared = BackgroundSensorRecorder()

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let motionStreamer = WatchMotionStreamer.shared

    // 状態管理
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var sessionState: String = "Idle"
    @Published var errorMessage: String?

    private var startTime: Date?
    private var durationTimer: Timer?

    private override init() {
        super.init()
        requestAuthorization()
    }

    // MARK: - Public Methods

    func startBackgroundRecording(rateHz: Int = 50, sensors: Set<WatchMotionStreamer.SensorType> = [.accelerometer]) {
        guard !isRecording else {
            print("Already recording")
            return
        }

        // ワークアウト設定
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other // センサー記録用のその他アクティビティ
        configuration.locationType = .unknown

        do {
            // ワークアウトセッションを作成
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.delegate = self

            // ライブワークアウトビルダーを作成
            if let session = workoutSession {
                workoutBuilder = session.associatedWorkoutBuilder()
                workoutBuilder?.delegate = self
                workoutBuilder?.dataSource = HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration: configuration
                )
            }

            // ワークアウト開始
            workoutSession?.startActivity(with: Date())
            workoutBuilder?.beginCollection(withStart: Date()) { success, error in
                if success {
                    print("Workout collection started successfully")

                    // モーションセンサー記録開始
                    DispatchQueue.main.async {
                        self.motionStreamer.start(rateHz: rateHz, sensors: sensors)
                        self.isRecording = true
                        self.startTime = Date()
                        self.startDurationTimer()
                        self.sessionState = "Recording"
                    }
                } else if let error = error {
                    print("Failed to start workout collection: \(error)")
                    self.errorMessage = error.localizedDescription
                }
            }

        } catch {
            print("Failed to create workout session: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    func stopBackgroundRecording() {
        guard isRecording else {
            print("Not recording")
            return
        }

        // モーションセンサー記録停止
        motionStreamer.stop()

        // タイマー停止
        durationTimer?.invalidate()
        durationTimer = nil

        // ワークアウト終了
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { success, error in
            if success {
                // ワークアウトを保存
                self.workoutBuilder?.finishWorkout { workout, error in
                    if let workout = workout {
                        print("Workout saved: \(workout)")
                    }
                    if let error = error {
                        print("Failed to save workout: \(error)")
                    }
                }
            } else if let error = error {
                print("Failed to end workout collection: \(error)")
            }
        }

        isRecording = false
        sessionState = "Stopped"
        recordingDuration = 0
        startTime = nil
    }

    func pauseRecording() {
        guard isRecording else { return }
        workoutSession?.pause()
        motionStreamer.stop()
        durationTimer?.invalidate()
        sessionState = "Paused"
    }

    func resumeRecording() {
        guard workoutSession != nil else { return }
        workoutSession?.resume()
        motionStreamer.start(rateHz: motionStreamer.currentRateHz, sensors: nil)
        startDurationTimer()
        sessionState = "Recording"
    }

    // MARK: - Private Methods

    private func requestAuthorization() {
        let typesToShare: Set<HKSampleType> = [
            HKWorkoutType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKWorkoutType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if !success {
                print("HealthKit authorization failed: \(String(describing: error))")
                self.errorMessage = "HealthKit認証に失敗しました"
            }
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = self.startTime {
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension BackgroundSensorRecorder: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didChangeTo toState: HKWorkoutSessionState,
                       from fromState: HKWorkoutSessionState,
                       date: Date) {

        DispatchQueue.main.async {
            switch toState {
            case .running:
                self.sessionState = "Running"
                print("Workout session is running")

            case .paused:
                self.sessionState = "Paused"
                print("Workout session is paused")

            case .stopped:
                self.sessionState = "Stopped"
                print("Workout session stopped")

            case .ended:
                self.sessionState = "Ended"
                print("Workout session ended")

            case .notStarted:
                self.sessionState = "Not Started"
                print("Workout session not started")

            case .prepared:
                self.sessionState = "Prepared"
                print("Workout session prepared")

            @unknown default:
                self.sessionState = "Unknown"
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            print("Workout session error: \(error)")
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didGenerate event: HKWorkoutEvent) {
        print("Workout event: \(event)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension BackgroundSensorRecorder: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                       didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // データ収集の通知（必要に応じて処理）
        for type in collectedTypes {
            print("Collected data type: \(type)")
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // イベント収集の通知
        print("Workout event collected")
    }
}