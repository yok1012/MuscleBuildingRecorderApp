import Foundation
import HealthKit
import Combine

class WorkoutManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0

    @Published var isWorkoutActive = false
    @Published var isPaused = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedTime: TimeInterval = 0

    private var timer: Timer?

    var elapsedTimeString: String {
        let time = Int(elapsedTime)
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func requestAuthorization() {
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]

        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit authorization failed: \(error)")
            }
        }
    }

    func startWorkout() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        do {
            workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            workoutSession?.delegate = self
            builder = workoutSession?.associatedWorkoutBuilder()
            builder?.delegate = self

            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession?.startActivity(with: Date())
            builder?.beginCollection(withStart: Date()) { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.isWorkoutActive = true
                        self.startTime = Date()
                        self.startTimer()
                    }
                }
            }
        } catch {
            print("Failed to start workout: \(error)")
        }
    }

    func endWorkout() {
        workoutSession?.end()
        builder?.endCollection(withEnd: Date()) { success, error in
            self.builder?.finishWorkout { workout, error in
                DispatchQueue.main.async {
                    self.isWorkoutActive = false
                    self.isPaused = false
                    self.stopTimer()
                    self.resetMetrics()
                }
            }
        }
    }

    func togglePause() {
        if isPaused {
            workoutSession?.resume()
            isPaused = false
            startTimer()
        } else {
            workoutSession?.pause()
            isPaused = true
            pausedTime = elapsedTime
            stopTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let startTime = self.startTime {
                self.elapsedTime = self.pausedTime + Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetMetrics() {
        heartRate = 0
        activeCalories = 0
        elapsedTime = 0
        startTime = nil
        pausedTime = 0
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didChangeTo toState: HKWorkoutSessionState,
                       from fromState: HKWorkoutSessionState,
                       date: Date) {
        // Handle state changes
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                       didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                       didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            switch quantityType {
            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    DispatchQueue.main.async {
                        self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                    }
                }

            case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
                if let statistics = workoutBuilder.statistics(for: quantityType) {
                    DispatchQueue.main.async {
                        self.activeCalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    }
                }

            default:
                break
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Handle workout events
    }
}