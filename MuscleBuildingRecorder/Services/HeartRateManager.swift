import Foundation
import Combine

struct HeartRateSample {
    let timestamp: Date
    let bpm: Double
}

class HeartRateManager: ObservableObject {
    static let shared = HeartRateManager()

    // MARK: - Published Properties
    @Published var currentHeartRate: Double = 0
    @Published var heartRateSlope: Double = 0
    @Published var selectedSourceType: HeartRateSourceType = .healthKit
    @Published var isConnected = false
    @Published var lastUpdateTime: Date?
    @Published var statusMessage: String = "未接続"
    
    /// 現在の心拍数ソースを示す（UI表示用）
    @Published var activeHeartRateSource: String = "なし"
    
    /// Watchからの心拍数を使用中かどうか
    @Published var isUsingWatchHeartRate: Bool = false
    
    /// iPhone単独モード（Watchなしで動作中）
    @Published var isStandaloneMode: Bool = false

    // MARK: - Private Properties
    private var currentSource: HeartRateSource?
    private var heartRateSamples: [HeartRateSample] = []
    private let sampleWindowSeconds: TimeInterval = 10.0
    private var cancellables = Set<AnyCancellable>()

    private let healthKitService = HealthKitHeartRateService()
    let bleService = BLEHeartRateService()  // UIからアクセス可能にするためpublic
    
    /// Watch心拍数のタイムアウト検出用
    private var lastWatchHeartRateTime: Date?
    private var watchHeartRateTimeoutTimer: Timer?
    private let watchHeartRateTimeoutInterval: TimeInterval = 10.0  // 10秒間Watch HRがなければフォールバック
    
    /// ローカルHealthKit監視が有効かどうか
    private var isLocalHealthKitActive: Bool = false

    // MARK: - Initialization
    private init() {
        setupHeartRateSubscription()
        setupWatchHeartRateSubscription()
        setupWatchConnectivityObserver()
    }

    // MARK: - Watch Heart Rate Subscription
    private func setupWatchHeartRateSubscription() {
        // Watch経由の心拍数を受信
        NotificationCenter.default.addObserver(
            forName: WatchConnectivityService.heartRateDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let heartRate = notification.userInfo?["heartRate"] as? Double,
                  heartRate > 0 else { return }
            
            // Watchからの心拍数を受信
            self.lastWatchHeartRateTime = Date()
            self.isUsingWatchHeartRate = true
            self.activeHeartRateSource = "Watch"
            self.isStandaloneMode = false
            
            // ローカルHealthKitが有効な場合、Watch優先で使用
            self.updateHeartRate(heartRate)
            
            // タイムアウトタイマーをリセット
            self.resetWatchHeartRateTimeoutTimer()
        }
    }
    
    // MARK: - Watch Connectivity Observer
    private func setupWatchConnectivityObserver() {
        // Watch接続状態の変化を監視
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WatchReachabilityChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            let isReachable = notification.userInfo?["isReachable"] as? Bool ?? false
            
            if isReachable {
                // Watchが接続された - Watch心拍数を待機
                print("HeartRateManager: Watch connected, waiting for Watch heart rate")
                self.activeHeartRateSource = "Watch待機中"
            } else {
                // Watchが切断された - iPhoneローカルにフォールバック
                print("HeartRateManager: Watch disconnected, falling back to local HealthKit")
                self.fallbackToLocalHealthKit()
            }
        }
    }
    
    // MARK: - Watch Heart Rate Timeout
    private func resetWatchHeartRateTimeoutTimer() {
        watchHeartRateTimeoutTimer?.invalidate()
        watchHeartRateTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: watchHeartRateTimeoutInterval,
            repeats: false
        ) { [weak self] _ in
            self?.handleWatchHeartRateTimeout()
        }
    }
    
    private func handleWatchHeartRateTimeout() {
        print("HeartRateManager: Watch heart rate timeout, checking fallback options")
        
        // Watch心拍数がタイムアウト - フォールバック判定
        if isUsingWatchHeartRate {
            isUsingWatchHeartRate = false
            
            // ローカルHealthKitが有効かチェック
            if isLocalHealthKitActive {
                activeHeartRateSource = "iPhone (HealthKit)"
            } else {
                // ローカルHealthKitを開始
                startLocalHeartRateMonitoring()
            }
        }
    }
    
    // MARK: - Local Heart Rate Monitoring (iPhone Standalone)
    /// iPhoneのHealthKitから直接心拍数を取得開始（Watch未接続時）
    func startLocalHeartRateMonitoring() {
        guard !isLocalHealthKitActive else {
            print("HeartRateManager: Local HealthKit already active")
            return
        }
        
        print("HeartRateManager: Starting local HealthKit heart rate monitoring")
        isStandaloneMode = true
        activeHeartRateSource = "iPhone (HealthKit自動取得)"

        // HealthKitHeartRateServiceのローカル監視メソッドを直接呼び出す
        // （WorkoutSession作成なしで、HealthKitからWatch心拍数を取得）
        healthKitService.startLocalHeartRateMonitoring()
        isLocalHealthKitActive = true
        isConnected = true
        // Watchアプリなしの場合、心拍数は約10分間隔でしか記録されない旨を表示
        statusMessage = "HealthKit監視中 (Watchバックグラウンドデータ)"
    }
    
    /// ローカルHealthKit監視を停止
    func stopLocalHeartRateMonitoring() {
        guard isLocalHealthKitActive else { return }
        
        print("HeartRateManager: Stopping local HealthKit heart rate monitoring")
        isLocalHealthKitActive = false
        
        // HealthKitHeartRateServiceのローカル監視を停止
        healthKitService.stopLocalHeartRateMonitoring()
        statusMessage = "未接続"
    }
    
    /// Watch心拍数がない場合のフォールバック処理
    private func fallbackToLocalHealthKit() {
        isUsingWatchHeartRate = false
        isStandaloneMode = true
        
        // Watch心拍数タイムアウトタイマーを停止
        watchHeartRateTimeoutTimer?.invalidate()
        watchHeartRateTimeoutTimer = nil
        
        // ローカルHealthKitを開始
        startLocalHeartRateMonitoring()
    }
    
    // MARK: - Best Heart Rate Source Selection
    /// 最適な心拍数ソースを自動選択
    func selectBestHeartRateSource() {
        let watchConnected = WatchConnectivityService.shared.isWatchConnected
        
        if watchConnected {
            // Watch接続中 - Watch心拍数を待機
            activeHeartRateSource = "Watch待機中"
            isStandaloneMode = false
            
            // タイムアウトタイマーを開始（Watchから心拍数が来なければフォールバック）
            resetWatchHeartRateTimeoutTimer()
        } else {
            // Watch未接続 - iPhoneローカルHealthKit
            fallbackToLocalHealthKit()
        }
    }
    
    // MARK: - Start/Stop Monitoring
    /// 心拍数モニタリングを開始（SessionManager から呼ばれる）
    func startMonitoring() {
        print("HeartRateManager: startMonitoring called")
        selectBestHeartRateSource()
    }
    
    /// 心拍数モニタリングを停止
    func stopMonitoring() {
        print("HeartRateManager: stopMonitoring called")
        
        watchHeartRateTimeoutTimer?.invalidate()
        watchHeartRateTimeoutTimer = nil
        
        if isLocalHealthKitActive {
            stopLocalHeartRateMonitoring()
        }
        
        isUsingWatchHeartRate = false
        isStandaloneMode = false
        activeHeartRateSource = "なし"
        currentHeartRate = 0
        heartRateSlope = 0
        heartRateSamples.removeAll()
    }

    // MARK: - Authorization
    func requestAuthorization() {
        Task {
            try? await healthKitService.requestAuthorization()
        }
    }

    // MARK: - Source Connection
    func connectToSource(_ type: HeartRateSourceType) async {
        print("HeartRateManager: Connecting to \(type)...")
        await disconnectCurrentSource()

        selectedSourceType = type
        statusMessage = "接続中..."
        let source: HeartRateSource

        switch type {
        case .healthKit:
            source = healthKitService
        case .bluetooth:
            source = bleService
        }

        do {
            try await source.connect()
            currentSource = source
            isConnected = true
            statusMessage = "\(type.rawValue)接続済み - データ待機中"
            print("HeartRateManager: Successfully connected to \(type)")
        } catch {
            print("HeartRateManager: Failed to connect to \(type): \(error)")
            isConnected = false
            statusMessage = "接続失敗: \(error.localizedDescription)"
        }
    }

    func disconnectCurrentSource() async {
        currentSource?.disconnect()
        currentSource = nil
        isConnected = false
        currentHeartRate = 0
        heartRateSlope = 0
        heartRateSamples.removeAll()
        lastUpdateTime = nil
        statusMessage = "未接続"
    }

    // MARK: - Heart Rate Subscription
    private func setupHeartRateSubscription() {
        Publishers.Merge(
            healthKitService.heartRatePublisher,
            bleService.heartRatePublisher
        )
        .sink { [weak self] heartRate in
            guard let self = self else { return }
            
            // Watch心拍数を使用中の場合、ローカルソースからの心拍数は無視
            // （Watchの方がリアルタイム性が高いため）
            if self.isUsingWatchHeartRate {
                return
            }
            
            self.updateHeartRate(heartRate)
        }
        .store(in: &cancellables)
    }

    private func updateHeartRate(_ bpm: Double) {
        guard bpm > 0 else { return }

        currentHeartRate = bpm
        lastUpdateTime = Date()
        
        // ソース別のステータスメッセージ
        if isUsingWatchHeartRate {
            statusMessage = "Watch接続済み"
        } else if isStandaloneMode {
            statusMessage = "iPhone (HealthKit)接続済み"
        } else {
            statusMessage = "\(selectedSourceType.rawValue)接続済み"
        }

        let sample = HeartRateSample(timestamp: Date(), bpm: bpm)
        heartRateSamples.append(sample)

        let cutoffTime = Date().addingTimeInterval(-sampleWindowSeconds)
        heartRateSamples = heartRateSamples.filter { $0.timestamp > cutoffTime }

        heartRateSlope = calculateHeartRateSlope()
    }

    // MARK: - Heart Rate Slope Calculation
    private func calculateHeartRateSlope() -> Double {
        guard heartRateSamples.count >= 2 else { return 0 }

        let n = Double(heartRateSamples.count)
        let referenceTime = heartRateSamples.first?.timestamp ?? Date()

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for sample in heartRateSamples {
            let x = sample.timestamp.timeIntervalSince(referenceTime)
            let y = sample.bpm

            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.0001 else { return 0 }

        let slopePerSecond = (n * sumXY - sumX * sumY) / denominator
        return slopePerSecond * 60
    }

    // MARK: - Statistics
    func getHeartRateStats() -> (avg: Double, max: Double, min: Double) {
        guard !heartRateSamples.isEmpty else { return (0, 0, 0) }

        let rates = heartRateSamples.map { $0.bpm }
        let avg = rates.reduce(0, +) / Double(rates.count)
        let max = rates.max() ?? 0
        let min = rates.min() ?? 0

        return (avg, max, min)
    }
}