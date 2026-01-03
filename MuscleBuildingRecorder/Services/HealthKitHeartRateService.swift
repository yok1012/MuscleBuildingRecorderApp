import HealthKit
import Combine
import Foundation

class HealthKitHeartRateService: HeartRateSource, ObservableObject {
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: Any? // HKLiveWorkoutBuilderを動的に扱う
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    private var query: HKQuery?
    private var observerQuery: HKObserverQuery?

    // ローカル心拍数監視用（Watchアプリ起動なしでHealthKitから取得）
    private var localObserverQuery: HKObserverQuery?
    private var localAnchoredQuery: HKAnchoredObjectQuery?
    private var localQueryAnchor: HKQueryAnchor?
    private var isLocalMonitoringActive: Bool = false

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

        // iPhone側でHealthKitから直接心拍データを取得
        // Note: Watch経由の心拍データは使用しない（安定性向上のため）
        try await startWorkoutSession()
        print("HealthKit: Workout session started")
        startHeartRateQuery()
        print("HealthKit: Heart rate query started - iPhone direct HealthKit mode")
    }

    func disconnect() {
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

    // MARK: - Local Heart Rate Monitoring (Without Watch App)

    /// Watchがバックグラウンドで記録する心拍数をリアルタイム監視
    /// Watchアプリを起動せずに、HealthKitに保存された心拍数を取得
    func startLocalHeartRateMonitoring() {
        guard !isLocalMonitoringActive else {
            print("HealthKit Local: Already monitoring")
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit Local: HealthKit not available")
            return
        }

        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            print("HealthKit Local: Failed to create heart rate type")
            return
        }

        print("HealthKit Local: Starting local heart rate monitoring (without Watch app)")

        // 認可を確認・リクエスト
        let typesToRead: Set<HKObjectType> = [heartRateType]
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            guard let self = self else { return }
            
            if let error = error {
                print("HealthKit Local: Authorization error: \(error.localizedDescription)")
                return
            }
            
            if !success {
                print("HealthKit Local: Authorization denied")
                return
            }
            
            // 認可状態を確認
            let status = self.healthStore.authorizationStatus(for: heartRateType)
            print("HealthKit Local: Authorization status: \(status.rawValue) (2=authorized)")
            
            DispatchQueue.main.async {
                self.isLocalMonitoringActive = true
                self.startLocalMonitoringQueries(heartRateType: heartRateType)
            }
        }
    }
    
    /// ローカル監視クエリを開始（認可後に呼ばれる）
    private func startLocalMonitoringQueries(heartRateType: HKQuantityType) {
        print("HealthKit Local: Starting queries...")
        
        // 1. ObserverQueryで新しいサンプル追加を監視
        localObserverQuery = HKObserverQuery(
            sampleType: heartRateType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            if let error = error {
                print("HealthKit Local: ObserverQuery error: \(error.localizedDescription)")
                completionHandler()
                return
            }

            print("HealthKit Local: ObserverQuery triggered - new data available")
            // 新しいサンプルが追加されたら、AnchoredQueryで取得
            self?.fetchLatestHeartRateLocal()
            completionHandler()
        }

        if let localObserverQuery = localObserverQuery {
            healthStore.execute(localObserverQuery)
            print("HealthKit Local: ObserverQuery started")
        }

        // 2. 初回データ取得（過去5分以内のデータを取得）
        fetchLatestHeartRateLocal()

        // 3. バックグラウンド配信を有効化（Watchが記録したら即通知）
        healthStore.enableBackgroundDelivery(
            for: heartRateType,
            frequency: .immediate
        ) { success, error in
            if success {
                print("HealthKit Local: Background delivery enabled for heart rate")
            } else if let error = error {
                print("HealthKit Local: Failed to enable background delivery: \(error.localizedDescription)")
            }
        }
    }

    /// 最新の心拍数を取得（Watchアプリなしでも心拍数取得可能）
    private func fetchLatestHeartRateLocal() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        let now = Date()
        // 過去15分以内のサンプルを取得
        // Watchアプリなしの場合、バックグラウンド心拍数記録は約10分間隔のため
        let fifteenMinutesAgo = now.addingTimeInterval(-900)

        let predicate = HKQuery.predicateForSamples(
            withStart: fifteenMinutesAgo,
            end: now,
            options: .strictEndDate
        )

        // 既存のクエリがあれば停止
        if let existingQuery = localAnchoredQuery {
            healthStore.stop(existingQuery)
        }

        print("HealthKit Local: Fetching heart rate samples from last 15 minutes...")

        // AnchoredObjectQueryで新しいサンプルのみ効率的に取得
        let anchoredQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: localQueryAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, anchor, error in
            guard let self = self else { return }

            if let error = error {
                print("HealthKit Local: AnchoredQuery error: \(error.localizedDescription)")
                return
            }

            let sampleCount = (samples as? [HKQuantitySample])?.count ?? 0
            print("HealthKit Local: Initial query found \(sampleCount) samples")

            // アンカーを保存（次回はこれ以降のデータのみ取得）
            self.localQueryAnchor = anchor

            // 最新の心拍数サンプルを取得
            self.processLocalHeartRateSamples(samples)
        }

        // 継続的な更新ハンドラ（新しいサンプルが追加されるたびに呼ばれる）
        anchoredQuery.updateHandler = { [weak self] _, samples, _, anchor, error in
            guard let self = self else { return }

            if let error = error {
                print("HealthKit Local: Update handler error: \(error.localizedDescription)")
                return
            }

            let sampleCount = (samples as? [HKQuantitySample])?.count ?? 0
            if sampleCount > 0 {
                print("HealthKit Local: Update received \(sampleCount) new samples")
            }

            self.localQueryAnchor = anchor
            self.processLocalHeartRateSamples(samples)
        }

        healthStore.execute(anchoredQuery)
        localAnchoredQuery = anchoredQuery
    }

    /// ローカル監視用の心拍数サンプル処理
    private func processLocalHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latestSample = quantitySamples.sorted(by: { $0.endDate > $1.endDate }).first else {
            return
        }

        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let heartRate = latestSample.quantity.doubleValue(for: heartRateUnit)
        let age = Date().timeIntervalSince(latestSample.endDate)

        // デバイスソースを確認（Watchからのデータか？）
        let sourceRevision = latestSample.sourceRevision
        let deviceName = sourceRevision.source.name
        let deviceModel = latestSample.device?.name ?? "Unknown"

        print("HealthKit Local: Heart rate: \(Int(heartRate)) bpm from \(deviceName) (\(deviceModel))")
        print("HealthKit Local: Sample age: \(Int(age))s, isAppleWatch: \(deviceName.contains("Watch") || deviceModel.contains("Watch"))")

        // 15分（900秒）以内のサンプルをUI更新
        // Watchアプリなしの場合、バックグラウンド心拍数記録は約10分間隔のため
        if age <= 900 {
            DispatchQueue.main.async {
                self.heartRateSubject.send(heartRate)
            }
            print("HealthKit Local: Sent heart rate \(Int(heartRate)) bpm to UI (age: \(Int(age))s)")
        } else {
            print("HealthKit Local: Sample too old (\(Int(age))s > 900s), not sending to UI")
        }
    }

    /// ローカル心拍数監視を停止
    func stopLocalHeartRateMonitoring() {
        guard isLocalMonitoringActive else {
            print("HealthKit Local: Not currently monitoring")
            return
        }

        print("HealthKit Local: Stopping local heart rate monitoring")

        if let localObserverQuery = localObserverQuery {
            healthStore.stop(localObserverQuery)
            self.localObserverQuery = nil
        }

        if let localAnchoredQuery = localAnchoredQuery {
            healthStore.stop(localAnchoredQuery)
            self.localAnchoredQuery = nil
        }

        // バックグラウンド配信を無効化
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            healthStore.disableBackgroundDelivery(for: heartRateType) { success, error in
                if success {
                    print("HealthKit Local: Background delivery disabled")
                } else if let error = error {
                    print("HealthKit Local: Failed to disable background delivery: \(error.localizedDescription)")
                }
            }
        }

        localQueryAnchor = nil
        isLocalMonitoringActive = false
    }
}
