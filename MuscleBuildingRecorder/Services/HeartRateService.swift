import Foundation
import Combine

protocol HeartRateSource {
    var isAvailable: Bool { get }
    var heartRatePublisher: AnyPublisher<Double, Never> { get }
    func connect() async throws
    func disconnect()
}

enum HeartRateSourceType: String, CaseIterable {
    case healthKit = "Apple Watch (HealthKit)"
    case bluetooth = "BLE心拍計"
    case airpods = "AirPods Pro"

    var icon: String {
        switch self {
        case .healthKit: return "applewatch"
        case .bluetooth: return "wifi"
        case .airpods: return "airpodspro"
        }
    }

    var description: String {
        switch self {
        case .healthKit: return "Apple WatchとHealthKit経由で心拍数を取得"
        case .bluetooth: return "Bluetooth Low Energy心拍計から取得"
        case .airpods: return "AirPods Proの心拍センサーを使用"
        }
    }
}