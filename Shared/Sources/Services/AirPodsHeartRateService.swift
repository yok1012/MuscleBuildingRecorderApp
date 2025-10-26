import Combine
import Foundation

class AirPodsHeartRateService: HeartRateSource, ObservableObject {
    private let heartRateSubject = CurrentValueSubject<Double, Never>(0)

    var isAvailable: Bool { false }

    var heartRatePublisher: AnyPublisher<Double, Never> {
        heartRateSubject.eraseToAnyPublisher()
    }

    func connect() async throws {
        throw HeartRateError.notSupported
    }

    func disconnect() {
    }

    var unsupportedMessage: String {
        "AirPods（第3世代）は心拍数測定に対応していません。Apple WatchまたはBluetooth心拍計をご利用ください。"
    }
}