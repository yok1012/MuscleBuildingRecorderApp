import CoreBluetooth
import Combine

// MARK: - CBCentralManagerDelegate
extension AirPodsHeartRateService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on, scanning for AirPods...")
            // AirPodsを探す
            central.scanForPeripherals(
                withServices: [heartRateServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .poweredOff:
            print("Bluetooth is powered off")
            isSearching = false
        case .unauthorized:
            print("Bluetooth is unauthorized")
            isSearching = false
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // AirPodsかどうかを確認
        if let name = peripheral.name?.lowercased(),
           name.contains("airpods") || name.contains("pods") {
            print("Found potential AirPods: \(peripheral.name ?? "Unknown")")

            airPodsPeripheral = peripheral
            airPodsPeripheral?.delegate = self
            central.stopScan()
            central.connect(peripheral, options: nil)
            isSearching = false
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to AirPods")
        peripheral.discoverServices([heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to AirPods: \(error?.localizedDescription ?? "Unknown error")")
        isSearching = false
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from AirPods")
        airPodsPeripheral = nil
        heartRateCharacteristic = nil
        heartRateSubject.send(0)
    }
}

// MARK: - CBPeripheralDelegate
extension AirPodsHeartRateService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("Error discovering services: \(error!)")
            return
        }

        if let services = peripheral.services {
            for service in services {
                if service.uuid == heartRateServiceUUID {
                    print("Found heart rate service")
                    peripheral.discoverCharacteristics([heartRateCharacteristicUUID], for: service)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("Error discovering characteristics: \(error!)")
            return
        }

        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == heartRateCharacteristicUUID {
                    print("Found heart rate characteristic")
                    heartRateCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error updating value: \(error!)")
            return
        }

        if characteristic.uuid == heartRateCharacteristicUUID {
            if let data = characteristic.value {
                let heartRate = parseHeartRate(from: data)
                heartRateSubject.send(Double(heartRate))
            }
        }
    }

    internal func parseHeartRate(from data: Data) -> Int {
        // 標準的な心拍数データフォーマットをパース
        guard data.count >= 2 else { return 0 }

        let bytes = [UInt8](data)
        let flags = bytes[0]

        // ビット0が0の場合は8ビット、1の場合は16ビット
        let is16Bit = (flags & 0x01) != 0

        if is16Bit && data.count >= 3 {
            // 16ビット値
            return Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            // 8ビット値
            return Int(bytes[1])
        }
    }
}