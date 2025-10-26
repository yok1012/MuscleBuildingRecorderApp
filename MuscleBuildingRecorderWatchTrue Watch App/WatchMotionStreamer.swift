import Foundation
import CoreMotion
import WatchConnectivity
import Combine

// 加速度ストリーマー（watchOS側）
class WatchMotionStreamer: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchMotionStreamer()

    // Motion関連
    private let motionManager = CMMotionManager()
    private var session: WCSession = WCSession.default

    // バッファ
    private var buffer: [(t: Int64, ax: Double, ay: Double, az: Double)] = []
    private let bufferLock = NSLock()
    private var timer: Timer?

    // 一時ファイル管理
    private var pendingFiles: [URL] = []
    private let fileManager = FileManager.default
    private var tempDirectory: URL {
        fileManager.temporaryDirectory.appendingPathComponent("AccelLogs")
    }

    // 状態管理
    @Published var isRunning: Bool = false
    @Published var currentRateHz: Int = 50
    @Published var sessionReachable: Bool = false
    @Published var pendingFileCount: Int = 0
    @Published var totalSamples: Int = 0
    @Published var lastError: String?

    private let dateFormatter: DateFormatter

    private override init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyyMMdd_HHmmss"

        super.init()
        setupSession()
        ensureTempDirectory()
        loadPendingFiles()
    }

    // MARK: - Public Methods

    func start(rateHz: Int) {
        guard !isRunning else { return }
        guard motionManager.isAccelerometerAvailable else {
            lastError = "Accelerometer not available"
            print("Accelerometer not available")
            return
        }

        currentRateHz = rateHz
        isRunning = true
        buffer.removeAll()
        totalSamples = 0

        // 加速度センサーの更新間隔を設定
        motionManager.accelerometerUpdateInterval = 1.0 / Double(rateHz)

        // 加速度データの取得開始
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self else { return }

            if let error = error {
                self.lastError = error.localizedDescription
                print("Accelerometer error: \(error)")
                return
            }

            guard let data = data else { return }

            // タイムスタンプ（ミリ秒）と加速度データを記録
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            let sample = (
                t: timestamp,
                ax: data.acceleration.x,
                ay: data.acceleration.y,
                az: data.acceleration.z
            )

            self.bufferLock.lock()
            self.buffer.append(sample)
            self.totalSamples += 1
            self.bufferLock.unlock()
        }

        // 0.5秒ごとにバッファを送信
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.flushBuffer()
        }

        // ステータスをiPhoneに通知
        sendStatus("logging")
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        motionManager.stopAccelerometerUpdates()
        timer?.invalidate()
        timer = nil

        // 残りのバッファを送信
        flushBuffer()

        // ステータスをiPhoneに通知
        sendStatus("stopped")
    }

    // MARK: - Private Methods

    private func setupSession() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    private func ensureTempDirectory() {
        if !fileManager.fileExists(atPath: tempDirectory.path) {
            try? fileManager.createDirectory(
                at: tempDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func loadPendingFiles() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            pendingFiles = files.filter { $0.pathExtension == "jsonl" }
            pendingFileCount = pendingFiles.count
        } catch {
            print("Failed to load pending files: \(error)")
        }
    }

    private func flushBuffer() {
        bufferLock.lock()
        let samplesToSend = buffer
        buffer.removeAll()
        bufferLock.unlock()

        guard !samplesToSend.isEmpty else { return }

        if session.isReachable {
            // 到達可能な場合は直接送信
            sendSamplesToPhone(samplesToSend)
        } else {
            // 到達不可の場合は一時ファイルに保存
            saveToTempFile(samplesToSend)
        }
    }

    private func sendSamplesToPhone(_ samples: [(t: Int64, ax: Double, ay: Double, az: Double)]) {
        // サンプルを配列形式に変換
        let samplesArray = samples.map { [$0.t, $0.ax, $0.ay, $0.az] }

        let message: [String: Any] = [
            "type": "accel",
            "samples": samplesArray
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send samples: \(error)")
            // 送信失敗時は一時ファイルに保存
            self.saveToTempFile(samples)
        }
    }

    private func saveToTempFile(_ samples: [(t: Int64, ax: Double, ay: Double, az: Double)]) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = "tmp_accel_\(timestamp).jsonl"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        var jsonLines = ""
        for sample in samples {
            let json: [String: Any] = [
                "t": sample.t,
                "ax": sample.ax,
                "ay": sample.ay,
                "az": sample.az
            ]

            if let data = try? JSONSerialization.data(withJSONObject: json),
               let line = String(data: data, encoding: .utf8) {
                jsonLines += line + "\n"
            }
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                // ファイルが存在する場合は追記
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                if let data = jsonLines.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                // 新規ファイル作成
                try jsonLines.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            // ペンディングファイルリストに追加
            if !pendingFiles.contains(fileURL) {
                pendingFiles.append(fileURL)
                pendingFileCount = pendingFiles.count
            }
        } catch {
            print("Failed to save temp file: \(error)")
        }
    }

    private func transferPendingFiles() {
        guard session.isReachable else { return }

        for fileURL in pendingFiles {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                // ファイルが存在しない場合はリストから削除
                pendingFiles.removeAll { $0 == fileURL }
                continue
            }

            session.transferFile(fileURL, metadata: ["type": "accel_log"])
        }
    }

    private func sendStatus(_ status: String) {
        let message: [String: Any] = [
            "status": status,
            "rateHz": currentRateHz,
            "pendingFiles": pendingFileCount,
            "totalSamples": totalSamples
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error)")
        } else {
            print("WCSession activated")
            sessionReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        sessionReachable = session.isReachable
        print("Session reachability changed: \(session.isReachable)")

        if session.isReachable {
            // 到達可能になったらペンディングファイルを送信
            transferPendingFiles()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Received message from iPhone: \(message)")

        guard let cmd = message["cmd"] as? String else { return }

        DispatchQueue.main.async {
            switch cmd {
            case "start":
                let rateHz = message["rateHz"] as? Int ?? 50
                self.start(rateHz: rateHz)

            case "stop":
                self.stop()

            case "updateRate":
                if let rateHz = message["rateHz"] as? Int, self.isRunning {
                    self.stop()
                    self.start(rateHz: rateHz)
                }

            case "status":
                self.sendStatus(self.isRunning ? "logging" : "stopped")

            default:
                print("Unknown command: \(cmd)")
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        // アプリケーションコンテキストからもコマンドを受信
        if let cmd = applicationContext["cmd"] as? String {
            self.session(session, didReceiveMessage: applicationContext)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            print("File transfer failed: \(error)")
        } else {
            print("File transfer completed: \(fileTransfer.file.fileURL)")

            // 送信成功したファイルを削除
            let fileURL = fileTransfer.file.fileURL
            pendingFiles.removeAll { $0 == fileURL }
            pendingFileCount = pendingFiles.count

            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                print("Failed to delete transferred file: \(error)")
            }
        }
    }
}