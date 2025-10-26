import HealthKit
import Combine
import Foundation

class HealthKitHeartRateService: HeartRateSource, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    private var query: HKAnchoredObjectQuery?

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    func requestAuthorization() async throws {
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            .quantityType(forIdentifier: .heartRate)!,
            .quantityType(forIdentifier: .activeEnergyBurned)!,
            .workoutType()
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func connect() async throws {
        try await requestAuthorization()
        try await startWorkoutSession()
        startHeartRateQuery()
    }

    func disconnect() {
        if let query {
            healthStore.stop(query)
            self.query = nil
        }
        workoutSession?.end()
        workoutSession = nil
        builder?.endCollection(withEnd: Date()) { success, error in
            if let error = error {
                print("Failed to end collection: \(error)")
            }
        }
        builder = nil
    }

    private func startWorkoutSession() async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        #if os(watchOS)
        workoutSession = try HKWorkoutSession(
            healthStore: healthStore,
            configuration: configuration
        )
        builder = workoutSession?.associatedWorkoutBuilder()
        if let session = workoutSession {
            healthStore.start(session)
        }
        #else
        workoutSession = nil
        builder = nil
        #endif

        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        workoutSession?.startActivity(with: Date())
        try await builder?.beginCollection(at: Date())
    }

    private func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        let startDate = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )

        query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("Heart rate query error: \(error)")
                return
            }

            self?.processHeartRateSamples(samples)
        }

        query?.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("Heart rate update error: \(error)")
                return
            }

            self?.processHeartRateSamples(samples)
        }

        healthStore.execute(query!)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample] else { return }

        for sample in samples {
            let heartRate = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            DispatchQueue.main.async {
                self.heartRateSubject.send(heartRate)
            }
        }
    }
}
