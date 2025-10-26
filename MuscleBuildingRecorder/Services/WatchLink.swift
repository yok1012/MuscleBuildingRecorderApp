import Foundation
import WatchConnectivity

// Watch接続コントローラー
final class WatchLink {
    static let shared = WatchLink()

    private let session: WCSession = WCSession.default
    private var isSessionActive = false

    private init() {
        setupSession()
    }

    private func setupSession() {
        if WCSession.isSupported() {
            session.activate()
        }
    }

    // MARK: - Public Methods

    func sendStartLogging(rateHz: Int) {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }

        let message: [String: Any] = [
            "cmd": "start",
            "rateHz": rateHz
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send start command: \(error)")
                // 到達不可の場合はapplication contextを更新
                self.updateApplicationContext(message)
            }
        } else {
            // 到達不可の場合はapplication contextを更新
            updateApplicationContext(message)
        }
    }

    func sendStopLogging() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }

        let message: [String: Any] = [
            "cmd": "stop"
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to send stop command: \(error)")
                // 到達不可の場合はapplication contextを更新
                self.updateApplicationContext(message)
            }
        } else {
            // 到達不可の場合はapplication contextを更新
            updateApplicationContext(message)
        }
    }

    func requestStatus() {
        guard WCSession.isSupported() else { return }

        let message: [String: Any] = [
            "cmd": "status"
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: { response in
                print("Status response: \(response)")
            }) { error in
                print("Failed to request status: \(error)")
            }
        }
    }

    func updateSamplingRate(rateHz: Int) {
        guard WCSession.isSupported() else { return }

        let message: [String: Any] = [
            "cmd": "updateRate",
            "rateHz": rateHz
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("Failed to update sampling rate: \(error)")
            }
        } else {
            updateApplicationContext(message)
        }
    }

    // MARK: - Private Methods

    private func updateApplicationContext(_ message: [String: Any]) {
        do {
            try session.updateApplicationContext(message)
            print("Updated application context: \(message)")
        } catch {
            print("Failed to update application context: \(error)")
        }
    }

    // MARK: - Connection Status

    var isWatchReachable: Bool {
        return session.isReachable
    }

    var isWatchPaired: Bool {
        return session.isPaired
    }

    var isWatchAppInstalled: Bool {
        return session.isWatchAppInstalled
    }
}