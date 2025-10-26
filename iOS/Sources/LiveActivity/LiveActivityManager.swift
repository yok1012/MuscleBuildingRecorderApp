import ActivityKit
import Foundation

class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<WorkoutAttributes>?

    private init() {}

    func startLiveActivity(
        phase: WorkoutPhase,
        elapsedTime: String,
        heartRate: Int,
        exercise: String,
        category: String,
        cycleIndex: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }

        let attributes = WorkoutAttributes(startTime: Date())
        let contentState = WorkoutAttributes.ContentState(
            phase: phase.rawValue,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            exercise: exercise,
            category: category,
            cycleIndex: cycleIndex
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
            print("Live Activity started: \(currentActivity?.id ?? "")")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateLiveActivity(
        phase: WorkoutPhase,
        elapsedTime: String,
        heartRate: Int,
        exercise: String,
        category: String,
        cycleIndex: Int
    ) {
        guard let activity = currentActivity else { return }

        let contentState = WorkoutAttributes.ContentState(
            phase: phase.rawValue,
            elapsedTime: elapsedTime,
            heartRate: heartRate,
            exercise: exercise,
            category: category,
            cycleIndex: cycleIndex
        )

        Task {
            await activity.update(using: contentState)
        }
    }

    func endLiveActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(
                using: activity.contentState,
                dismissalPolicy: .immediate
            )
        }

        currentActivity = nil
    }

    func isLiveActivityActive() -> Bool {
        return currentActivity != nil
    }
}

extension SessionManager {
    func setupLiveActivity() {
        guard currentPhase != .idle else { return }

        let liveActivityManager = LiveActivityManager.shared

        if !liveActivityManager.isLiveActivityActive() {
            liveActivityManager.startLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: Int(HeartRateManager.shared.currentHeartRate),
                exercise: selectedExercise,
                category: selectedCategory,
                cycleIndex: cycleIndex
            )
        } else {
            liveActivityManager.updateLiveActivity(
                phase: currentPhase,
                elapsedTime: elapsedTimeString,
                heartRate: Int(HeartRateManager.shared.currentHeartRate),
                exercise: selectedExercise,
                category: selectedCategory,
                cycleIndex: cycleIndex
            )
        }

        if currentPhase == .idle {
            liveActivityManager.endLiveActivity()
        }
    }
}