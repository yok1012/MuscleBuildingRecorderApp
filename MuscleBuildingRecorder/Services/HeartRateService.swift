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

    var icon: String {
        switch self {
        case .healthKit: return "applewatch"
        case .bluetooth: return "heart.circle"
        }
    }

    var description: String {
        switch self {
        case .healthKit: return "Apple WatchとHealthKit経由で心拍数を取得"
        case .bluetooth: return "Bluetooth心拍計から取得（Polar等）"
        }
    }
}