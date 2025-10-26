import HealthKit
import Combine
import Foundation
import WatchConnectivity

class HealthKitHeartRateService: HeartRateSource, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: Any? // HKLiveWorkoutBuilderを動的に扱う
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    private var query: HKQuery?
    private var observerQuery: HKObserverQuery?
    private var watchConnectivity = WatchConnectivityService.shared
    private var watchCancellable: AnyCancellable?

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

        // Check authorization status
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let authStatus = healthStore.authorizationStatus(for: heartRateType)
        print("HealthKit: Heart rate authorization status: \(authStatus.rawValue) (0=notDetermined, 1=sharingDenied, 2=sharingAuthorized)")
    }

    func connect() async throws {
        print("HealthKit: Starting connection...")
        try await requestAuthorization()
        print("HealthKit: Authorization granted")

        // Watch Connectivityからの心拍数データを購読
        watchCancellable = watchConnectivity.heartRatePublisher
            .sink { [weak self] heartRate in
                print("HealthKit: Received heart rate from Watch: \(heartRate)")
                self?.heartRateSubject.send(heartRate)
            }

        // Watchにワークアウト開始を通知
        watchConnectivity.startWatchWorkout()
        print("HealthKit: Sent start command to Watch")

        // iPhone側でもワークアウトセッションを開始（バックアップ）
        try await startWorkoutSession()
        print("HealthKit: Workout session started")
        startHeartRateQuery()
        print("HealthKit: Heart rate query started")
    }

    func disconnect() {
        watchCancellable?.cancel()
        watchCancellable = nil
        watchConnectivity.stopWatchWorkout()

        if let query {
            healthStore.stop(query)
            self.query = nil
        }
        if let observerQuery {
            healthStore.stop(observerQuery)
            self.observerQuery = nil
        }
        workoutSession?.end()
        workoutSession = nil

        if #available(iOS 26.0, watchOS 9.0, *) {
            if let workoutBuilder = builder as? HKLiveWorkoutBuilder {
                workoutBuilder.endCollection(withEnd: Date()) { success, error in
                    if let error = error {
                        print("Failed to end collection: \(error)")
                    }
                }
            }
            builder = nil
        }
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

        if #available(watchOS 9.0, iOS 26.0, *) {
            if let workoutBuilder = workoutSession?.associatedWorkoutBuilder() {
                builder = workoutBuilder
                workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration: configuration
                )

                workoutSession?.startActivity(with: Date())
                try await workoutBuilder.beginCollection(at: Date())
            }
        } else {
            if let session = workoutSession {
                healthStore.start(session)
            }
        }
        #else
        // iOS側では、ワークアウトセッションを作成せず、心拍数のクエリのみを使用
        workoutSession = nil
        #endif
    }

    private func startHeartRateQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            print("HealthKit: Failed to create heart rate type")
            return
        }

        #if os(iOS)
        // For iOS, use HKSampleQuery to get the most recent samples
        startIOSHeartRateQuery(heartRateType: heartRateType)
        #else
        // For watchOS, use HKAnchoredObjectQuery for real-time updates
        startWatchOSHeartRateQuery(heartRateType: heartRateType)
        #endif
    }

    private func startIOSHeartRateQuery(heartRateType: HKQuantityType) {
        print("HealthKit iOS: Starting real-time heart rate monitoring")

        // Use HKAnchoredObjectQuery for real-time streaming updates
        let anchoredQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,  // No predicate to get all samples
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("HealthKit iOS: Initial anchored query error: \(error)")
                return
            }

            print("HealthKit iOS: Initial query found \(samples?.count ?? 0) samples")
            if let samples = samples as? [HKQuantitySample] {
                // Get only the most recent sample from initial batch
                let recentSamples = samples.filter { sample in
                    Date().timeIntervalSince(sample.startDate) <= 60  // Last minute only
                }.sorted { $0.startDate > $1.startDate }

                if let mostRecent = recentSamples.first {
                    let bpm = mostRecent.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    print("HealthKit iOS: Most recent: \(bpm) bpm at \(mostRecent.startDate)")
                    print("  Device: \(mostRecent.device?.name ?? "Unknown")")
                    print("  Source: \(mostRecent.sourceRevision.source.name)")
                    self?.processHeartRateSamples([mostRecent])
                }
            }
        }

        // Set up update handler for streaming updates
        anchoredQuery.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("HealthKit iOS: Update handler error: \(error)")
                return
            }

            if let samples = samples as? [HKQuantitySample], !samples.isEmpty {
                print("HealthKit iOS: Received \(samples.count) new heart rate samples")
                for sample in samples {
                    let bpm = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    print("  New sample: \(bpm) bpm at \(sample.startDate)")
                    print("    Device: \(sample.device?.name ?? "Unknown")")
                    print("    Source: \(sample.sourceRevision.source.name)")
                }
                // Process all new samples immediately
                self?.processHeartRateSamples(samples)
            }
        }

        query = anchoredQuery
        healthStore.execute(anchoredQuery)
        print("HealthKit iOS: Anchored query started for real-time updates")

        // Also enable background delivery for heart rate updates
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if success {
                print("HealthKit iOS: Background delivery enabled for heart rate")
            } else if let error = error {
                print("HealthKit iOS: Failed to enable background delivery: \(error)")
            }
        }
    }

    private func startWatchOSHeartRateQuery(heartRateType: HKQuantityType) {
        print("HealthKit watchOS: Starting heart rate monitoring")

        let startDate = Date().addingTimeInterval(-60)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: []
        )

        let anchoredQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            if let error = error {
                print("HealthKit watchOS: Initial query error: \(error)")
                return
            }

            print("HealthKit watchOS: Initial query returned \(samples?.count ?? 0) samples")
            self?.processHeartRateSamples(samples)
        }

        anchoredQuery.updateHandler = { [weak self] _, samples, _, _, error in
            if let error = error {
                print("HealthKit watchOS: Update handler error: \(error)")
                return
            }

            print("HealthKit watchOS: Update received \(samples?.count ?? 0) new samples")
            self?.processHeartRateSamples(samples)
        }

        query = anchoredQuery
        healthStore.execute(anchoredQuery)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
            print("HealthKit: No valid samples to process")
            return
        }

        for sample in samples {
            let heartRate = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            let age = Date().timeIntervalSince(sample.startDate)
            print("HealthKit: Processed heart rate: \(heartRate) bpm at \(sample.startDate) (\(Int(age))s ago)")

            // Send all samples that are within 2 minutes (to handle slight delays)
            #if os(iOS)
            if age <= 120 { // 2 minutes window
                DispatchQueue.main.async {
                    print("HealthKit: Sending heart rate to UI: \(heartRate) bpm (from \(Int(age))s ago)")
                    self.heartRateSubject.send(heartRate)
                }
            } else {
                print("HealthKit: Sample too old, not sending (\(Int(age))s ago)")
            }
            #else
            // For watchOS, send all samples as they should be real-time
            DispatchQueue.main.async {
                self.heartRateSubject.send(heartRate)
            }
            #endif
        }
    }
}
