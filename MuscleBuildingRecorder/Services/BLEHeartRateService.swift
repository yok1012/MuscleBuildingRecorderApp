import CoreBluetooth
import Combine
import Foundation

/// 発見されたBLEデバイス
struct DiscoveredBLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    static func == (lhs: DiscoveredBLEDevice, rhs: DiscoveredBLEDevice) -> Bool {
        lhs.id == rhs.id
    }
}

class BLEHeartRateService: NSObject, HeartRateSource, ObservableObject {
    private let heartRateServiceUUID = CBUUID(string: "0x180D")
    private let heartRateMeasurementCharUUID = CBUUID(string: "0x2A37")

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    // MARK: - Published Properties
    /// 発見されたデバイス一覧
    @Published var discoveredDevices: [DiscoveredBLEDevice] = []

    /// 接続中のデバイス名
    @Published var connectedDeviceName: String?

    /// スキャン中かどうか
    @Published var isScanning: Bool = false

    /// 接続状態
    @Published var connectionState: BLEConnectionState = .disconnected

    /// 最後のエラーメッセージ
    @Published var lastError: String?

    // MARK: - Private Properties
    /// 保存されたデバイスUUID（自動再接続用）
    private let savedDeviceUUIDKey = "BLEHeartRateDeviceUUID"

    /// スキャンタイムアウトタイマー
    private var scanTimeoutTimer: Timer?

    /// 接続完了ハンドラ
    private var connectionCompletion: ((Result<Void, Error>) -> Void)?

    var isAvailable: Bool {
        centralManager?.state == .poweredOn
    }

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    /// 保存されたデバイスUUID
    var savedDeviceUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: savedDeviceUUIDKey) else {
                return nil
            }
            return UUID(uuidString: uuidString)
        }
        set {
            if let uuid = newValue {
                UserDefaults.standard.set(uuid.uuidString, forKey: savedDeviceUUIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: savedDeviceUUIDKey)
            }
        }
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - HeartRateSource Protocol
    func connect() async throws {
        guard centralManager.state == .poweredOn else {
            throw HeartRateError.bluetoothUnavailable
        }

        // 保存されたデバイスがあれば自動再接続を試みる
        if let savedUUID = savedDeviceUUID {
            let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [savedUUID])
            if let peripheral = knownPeripherals.first {
                try await connectToPeripheral(peripheral)
                return
            }
        }

        // デバイスがない場合はスキャンを開始
        startScanning()
    }

    func disconnect() {
        stopScanning()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        connectedDeviceName = nil
        connectionState = .disconnected
        heartRateSubject.send(0)
    }

    // MARK: - Scanning
    /// デバイススキャンを開始
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetoothが無効です"
            return
        }

        discoveredDevices.removeAll()
        isScanning = true
        lastError = nil

        centralManager.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // 30秒後にスキャン停止
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }

        print("BLEHeartRateService: Started scanning for heart rate devices")
    }

    /// デバイススキャンを停止
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        print("BLEHeartRateService: Stopped scanning")
    }

    // MARK: - Connection
    /// 指定したデバイスに接続
    func connectToDevice(_ device: DiscoveredBLEDevice) {
        stopScanning()
        connectionState = .connecting
        lastError = nil

        device.peripheral.delegate = self
        centralManager.connect(device.peripheral, options: nil)

        print("BLEHeartRateService: Connecting to \(device.name)")
    }

    /// CBPeripheralに直接接続（async版）
    private func connectToPeripheral(_ peripheral: CBPeripheral) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connectionCompletion = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            connectionState = .connecting
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)

            // タイムアウト処理
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                if self?.connectionState == .connecting {
                    self?.centralManager.cancelPeripheralConnection(peripheral)
                    self?.connectionCompletion?(.failure(HeartRateError.timeout))
                    self?.connectionCompletion = nil
                }
            }
        }
    }

    /// 保存されたデバイスに再接続
    func reconnect() async throws {
        guard let savedUUID = savedDeviceUUID else {
            throw HeartRateError.deviceNotFound
        }

        let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [savedUUID])
        guard let peripheral = knownPeripherals.first else {
            // 保存されたデバイスが見つからない場合はスキャン開始
            savedDeviceUUID = nil
            startScanning()
            throw HeartRateError.deviceNotFound
        }

        try await connectToPeripheral(peripheral)
    }

    /// 保存されたデバイスをクリア
    func forgetDevice() {
        disconnect()
        savedDeviceUUID = nil
        connectedDeviceName = nil
    }

    // MARK: - Heart Rate Parsing
    private func parseHeartRate(from data: Data) -> Double {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return 0 }

        let flags = bytes[0]
        let is16Bit = flags & 0x01 == 0x01

        if is16Bit {
            guard bytes.count >= 3 else { return 0 }
            let heartRate = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return Double(heartRate)
        } else {
            return Double(bytes[1])
        }
    }
}

// MARK: - Connection State
enum BLEConnectionState {
    case disconnected
    case connecting
    case connected
    case discovering
}

// MARK: - CBCentralManagerDelegate
extension BLEHeartRateService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("BLEHeartRateService: Bluetooth is ready")
        case .poweredOff:
            lastError = "Bluetoothがオフです"
            connectionState = .disconnected
        case .unauthorized:
            lastError = "Bluetooth使用が許可されていません"
        case .unsupported:
            lastError = "このデバイスはBLEをサポートしていません"
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "不明なデバイス"

        let device = DiscoveredBLEDevice(
            id: peripheral.identifier,
            name: deviceName,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )

        // 重複を避けて追加
        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            DispatchQueue.main.async {
                self.discoveredDevices.append(device)
                self.discoveredDevices.sort { $0.rssi > $1.rssi } // 信号強度順にソート
            }
            print("BLEHeartRateService: Discovered device: \(deviceName) (RSSI: \(RSSI))")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BLEHeartRateService: Connected to \(peripheral.name ?? "Unknown")")

        connectedPeripheral = peripheral
        connectedDeviceName = peripheral.name ?? "不明なデバイス"
        connectionState = .discovering

        // デバイスUUIDを保存（次回自動接続用）
        savedDeviceUUID = peripheral.identifier

        peripheral.discoverServices([heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("BLEHeartRateService: Failed to connect: \(error?.localizedDescription ?? "Unknown error")")

        connectionState = .disconnected
        lastError = "接続に失敗しました: \(error?.localizedDescription ?? "不明なエラー")"

        connectionCompletion?(.failure(error ?? HeartRateError.connectionFailed))
        connectionCompletion = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("BLEHeartRateService: Disconnected from \(peripheral.name ?? "Unknown")")

        connectedPeripheral = nil
        connectionState = .disconnected
        heartRateSubject.send(0)

        if let error = error {
            lastError = "切断されました: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEHeartRateService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            lastError = "サービス検出エラー: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == heartRateServiceUUID {
                peripheral.discoverCharacteristics([heartRateMeasurementCharUUID], for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            lastError = "特性検出エラー: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == heartRateMeasurementCharUUID {
                peripheral.setNotifyValue(true, for: characteristic)

                connectionState = .connected
                connectionCompletion?(.success(()))
                connectionCompletion = nil

                print("BLEHeartRateService: Subscribed to heart rate notifications")
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == heartRateMeasurementCharUUID,
              let data = characteristic.value else { return }

        let heartRate = parseHeartRate(from: data)
        DispatchQueue.main.async {
            self.heartRateSubject.send(heartRate)
        }
    }
}

enum HeartRateError: LocalizedError {
    case bluetoothUnavailable
    case notSupported
    case connectionFailed
    case deviceNotFound
    case timeout

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetoothが利用できません"
        case .notSupported:
            return "このデバイスは心拍数測定に対応していません"
        case .connectionFailed:
            return "接続に失敗しました"
        case .deviceNotFound:
            return "デバイスが見つかりません"
        case .timeout:
            return "接続がタイムアウトしました"
        }
    }
}
