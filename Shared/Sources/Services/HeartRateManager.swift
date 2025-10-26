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

    private var currentSource: HeartRateSource?
    private var heartRateSamples: [HeartRateSample] = []
    private let sampleWindowSeconds: TimeInterval = 10.0
    private var cancellables = Set<AnyCancellable>()

    private let healthKitService = HealthKitHeartRateService()
    private let bleService = BLEHeartRateService()
    private let airPodsService = AirPodsHeartRateService()

    private init() {
        setupHeartRateSubscription()
    }

    func requestAuthorization() {
        Task {
            try? await healthKitService.requestAuthorization()
        }
    }

    func connectToSource(_ type: HeartRateSourceType) async {
        await disconnectCurrentSource()

        selectedSourceType = type
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
        } catch {
            print("Failed to connect to \(type): \(error)")
            isConnected = false
        }
    }

    func disconnectCurrentSource() async {
        currentSource?.disconnect()
        currentSource = nil
        isConnected = false
        currentHeartRate = 0
        heartRateSlope = 0
        heartRateSamples.removeAll()
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

        currentHeartRate = bpm

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