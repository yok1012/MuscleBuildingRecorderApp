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
        phaseStartTime: Date?,
        domain: String = "workout"
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
                phaseStartTime: phaseStartTime,
                domain: domain
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
            phaseStartTime: phaseStartTime,
            domain: domain
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
        phaseStartTime: Date?,
        domain: String = "workout"
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
            phaseStartTime: phaseStartTime,
            domain: domain
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

        // study/work では category/exercise の代わりに subject/taskName を表示用に流す
        let displayExercise = activeDomain == .workout
            ? selectedExercise
            : currentTaskName
        let displayCategory = activeDomain == .workout
            ? selectedCategory
            : (activeDomain == .study ? currentSubject : currentProject)

        if manager.isLiveActivityActive() {
            manager.updateLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: heartRate,
                exercise: displayExercise,
                category: displayCategory,
                cycleIndex: cycleIndex,
                load: currentLoad,
                reps: currentReps,
                phaseStartTime: phaseStartTime,
                domain: activeDomain.rawValue
            )
        } else {
            manager.startLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: heartRate,
                exercise: displayExercise,
                category: displayCategory,
                cycleIndex: cycleIndex,
                load: currentLoad,
                reps: currentReps,
                phaseStartTime: phaseStartTime,
                domain: activeDomain.rawValue
            )
        }
    }
}
