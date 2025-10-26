import CoreBluetooth
import Combine
import Foundation

class BLEHeartRateService: NSObject, HeartRateSource, ObservableObject {
    private let heartRateServiceUUID = CBUUID(string: "0x180D")
    private let heartRateMeasurementCharUUID = CBUUID(string: "0x2A37")

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    var isAvailable: Bool {
        centralManager?.state == .poweredOn
    }

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connect() async throws {
        guard centralManager.state == .poweredOn else {
            throw HeartRateError.bluetoothUnavailable
        }

        centralManager.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: nil
        )
    }

    func disconnect() {
        centralManager.stopScan()
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

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

extension BLEHeartRateService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth is ready")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }
}

extension BLEHeartRateService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
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
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == heartRateMeasurementCharUUID {
                peripheral.setNotifyValue(true, for: characteristic)
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