import Foundation
import Combine

struct HeartRateSample {
    let timestamp: Date
    let bpm: Double
}

class HeartRateManager: ObservableObject {
    static let shared = HeartRateManager()

    @Published var currentHeartRate: Double = 0
    @Published var heartRateSlope: Double = 0
    @Published var selectedSourceType: HeartRateSourceType = .healthKit
    @Published var isConnected = false
    @Published var lastUpdateTime: Date?
    @Published var statusMessage: String = "未接続"

    private var currentSource: HeartRateSource?
    private var heartRateSamples: [HeartRateSample] = []
    private let sampleWindowSeconds: TimeInterval = 10.0
    private var cancellables = Set<AnyCancellable>()

    private let healthKitService = HealthKitHeartRateService()
    private let bleService = BLEHeartRateService()
    let airPodsService = AirPodsHeartRateService()  // publicに変更してUIからアクセス可能に

    private init() {
        setupHeartRateSubscription()
    }

    func requestAuthorization() {
        Task {
            try? await healthKitService.requestAuthorization()
        }
    }

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
        case .airpods:
            source = airPodsService
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

    private func setupHeartRateSubscription() {
        Publishers.Merge3(
            healthKitService.heartRatePublisher,
            bleService.heartRatePublisher,
            airPodsService.heartRatePublisher
        )
        .sink { [weak self] heartRate in
            self?.updateHeartRate(heartRate)
        }
        .store(in: &cancellables)
    }

    private func updateHeartRate(_ bpm: Double) {
        guard bpm > 0 else { return }

        print("HeartRateManager: Received heart rate: \(bpm) bpm")
        currentHeartRate = bpm
        lastUpdateTime = Date()
        statusMessage = "\(selectedSourceType.rawValue)接続済み"

        let sample = HeartRateSample(timestamp: Date(), bpm: bpm)
        heartRateSamples.append(sample)

        let cutoffTime = Date().addingTimeInterval(-sampleWindowSeconds)
        heartRateSamples = heartRateSamples.filter { $0.timestamp > cutoffTime }

        heartRateSlope = calculateHeartRateSlope()
    }

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

    func getHeartRateStats() -> (avg: Double, max: Double, min: Double) {
        guard !heartRateSamples.isEmpty else { return (0, 0, 0) }

        let rates = heartRateSamples.map { $0.bpm }
        let avg = rates.reduce(0, +) / Double(rates.count)
        let max = rates.max() ?? 0
        let min = rates.min() ?? 0

        return (avg, max, min)
    }
}