import ActivityKit
import Foundation

final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutAttributes>?

    private init() {
        // アプリ再起動直後に既存の Activity を拾い直す（currentActivity は memory-only なので
        // kill 後は nil から始まる。OS 側に残っている Activity と二重登録しないようここで接続）
        restoreExistingActivityIfNeeded()
    }

    // MARK: - Lifecycle

    func startLiveActivity(
        phase: WorkoutPhase,
        elapsedTime: String,
        heartRate: Int,
        exercise: String,
        category: String,
        cycleIndex: Int,
        load: Double,
        reps: Double,
        phaseStartTime: Date?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("LiveActivityManager: ⚠️ Live Activities are not enabled")
            return
        }

        // 既存の Activity があれば起動しない（ダブり防止）
        if currentActivity == nil {
            restoreExistingActivityIfNeeded()
        }
        if currentActivity != nil {
            // 既存を update 側に回す
            updateLiveActivity(
                phase: phase,
                elapsedTime: elapsedTime,
                heartRate: heartRate,
                exercise: exercise,
                category: category,
                cycleIndex: cycleIndex,
                load: load,
                reps: reps,
                phaseStartTime: phaseStartTime
            )
            return
        }

        let attributes = WorkoutAttributes(startTime: Date())
        let contentState = WorkoutAttributes.ContentState(
            phase: phase.rawValue,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            exercise: exercise,
            category: category,
            cycleIndex: cycleIndex,
            load: load,
            reps: reps,
            phaseStartTime: phaseStartTime
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            print("LiveActivityManager: ✅ Live Activity started id=\(currentActivity?.id ?? "-")")
        } catch {
            print("LiveActivityManager: ❌ Failed to start Live Activity: \(error)")
        }
    }

    func updateLiveActivity(
        phase: WorkoutPhase,
        elapsedTime: String,
        heartRate: Int,
        exercise: String,
        category: String,
        cycleIndex: Int,
        load: Double,
        reps: Double,
        phaseStartTime: Date?
    ) {
        guard let activity = currentActivity else { return }

        let contentState = WorkoutAttributes.ContentState(
            phase: phase.rawValue,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            exercise: exercise,
            category: category,
            cycleIndex: cycleIndex,
            load: load,
            reps: reps,
            phaseStartTime: phaseStartTime
        )

        Task {
            await activity.update(using: contentState)
        }
    }

    func endLiveActivity() {
        let activity = currentActivity
        currentActivity = nil

        guard let activity else { return }

        Task {
            await activity.end(
                using: activity.contentState,
                dismissalPolicy: .immediate
            )
        }
    }

    func isLiveActivityActive() -> Bool {
        currentActivity != nil
    }

    // MARK: - Private
    private func restoreExistingActivityIfNeeded() {
        // OS に残っている同 Attributes 型の Activity を拾う
        if let existing = Activity<WorkoutAttributes>.activities.first {
            currentActivity = existing
            print("LiveActivityManager: 🔄 Restored existing activity id=\(existing.id)")
        }
    }
}

// MARK: - SessionManager Integration
extension SessionManager {
    func setupLiveActivity() {
        guard currentPhase != .idle else {
            LiveActivityManager.shared.endLiveActivity()
            return
        }

        let manager = LiveActivityManager.shared
        let heartRate = Int(HeartRateManager.shared.currentHeartRate)

        if manager.isLiveActivityActive() {
            manager.updateLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: heartRate,
                exercise: selectedExercise,
                category: selectedCategory,
                cycleIndex: cycleIndex,
                load: currentLoad,
                reps: currentReps,
                phaseStartTime: phaseStartTime
            )
        } else {
            manager.startLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: heartRate,
                exercise: selectedExercise,
                category: selectedCategory,
                cycleIndex: cycleIndex,
                load: currentLoad,
                reps: currentReps,
                phaseStartTime: phaseStartTime
            )
        }
    }
}
