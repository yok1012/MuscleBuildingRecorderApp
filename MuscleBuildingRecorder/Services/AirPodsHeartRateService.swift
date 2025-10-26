import Combine
import Foundation
import CoreBluetooth
import AVFoundation

class AirPodsHeartRateService: NSObject, HeartRateSource, ObservableObject {
    internal let heartRateSubject = CurrentValueSubject<Double, Never>(0)
    internal var centralManager: CBCentralManager?
    internal var airPodsPeripheral: CBPeripheral?
    internal var heartRateCharacteristic: CBCharacteristic?
    internal var audioSession = AVAudioSession.sharedInstance()
    internal var isSearching = false

    // AirPodsのサービスUUID（推定値 - 実際のUUIDは異なる可能性があります）
    internal let airPodsServiceUUID = CBUUID(string: "FDB4") // Apple Continuity Service
    internal let heartRateServiceUUID = CBUUID(string: "180D") // Standard Heart Rate Service
    internal let heartRateCharacteristicUUID = CBUUID(string: "2A37") // Heart Rate Measurement

    var isAvailable: Bool {
        // AirPodsが接続されているかチェック
        checkAirPodsConnection()
    }

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        setupNotifications()
    }

    private func setupNotifications() {
        // オーディオルート変更の監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func audioRouteChanged(notification: Notification) {
        if checkAirPodsConnection() {
            print("AirPods detected in audio route")
        }
    }

    private func checkAirPodsConnection() -> Bool {
        let currentRoute = audioSession.currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP {
                if output.portName.lowercased().contains("airpods") {
                    return true
                }
            }
        }
        return false
    }

    func connect() async throws {
        guard checkAirPodsConnection() else {
            throw HeartRateError.deviceNotFound
        }

        // Bluetooth Central Managerを初期化
        await MainActor.run {
            centralManager = CBCentralManager(delegate: self, queue: nil)
            isSearching = true
        }

        // 接続タイムアウト
        try await withTimeout(seconds: 10) {
            while self.airPodsPeripheral == nil && self.isSearching {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒待機
            }
        }

        guard airPodsPeripheral != nil else {
            throw HeartRateError.connectionFailed
        }
    }

    func disconnect() {
        if let peripheral = airPodsPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        airPodsPeripheral = nil
        heartRateCharacteristic = nil
        centralManager = nil
        heartRateSubject.send(0)
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HeartRateError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Simulated Data for Development
    func startSimulatedData() {
        print("AirPods: Starting simulated heart rate data")

        // シミュレートデータの生成
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // リアルな心拍数のシミュレーション (60-100 bpm)
            let baseRate = 70.0
            let variation = sin(Date().timeIntervalSince1970 / 10.0) * 15.0
            let noise = Double.random(in: -3...3)
            let simulatedHeartRate = max(60, min(100, baseRate + variation + noise))

            self?.heartRateSubject.send(simulatedHeartRate)
        }
    }

    // MARK: - Heart Rate Data Processing
    private func processHeartRateData(_ data: Data) {
        guard data.count >= 2 else {
            print("AirPods: Invalid heart rate data")
            return
        }

        let bytes = [UInt8](data)
        let flags = bytes[0]

        // ビット0が0なら8ビット、1なら16ビット
        let is16Bit = (flags & 0x01) != 0
        var heartRateValue: UInt16 = 0

        if is16Bit && data.count >= 3 {
            heartRateValue = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        } else {
            heartRateValue = UInt16(bytes[1])
        }

        heartRateSubject.send(Double(heartRateValue))
        print("AirPods: Heart rate updated: \(heartRateValue) bpm")
    }
}