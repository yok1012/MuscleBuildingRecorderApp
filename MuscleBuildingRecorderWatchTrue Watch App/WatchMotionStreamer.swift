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
    private var buffer: [(
        t: Int64,
        ax: Double, ay: Double, az: Double,
        gx: Double?, gy: Double?, gz: Double?,
        pitch: Double?, roll: Double?, yaw: Double?,
        qx: Double?, qy: Double?, qz: Double?, qw: Double?
    )] = []
    private let bufferLock = NSLock()
    private let maxBufferSize = 1000 // メモリ保護: ~80KB max

    // データタイプ
    enum SensorType: String, CaseIterable {
        case accelerometer = "accel"
        case gyroscope = "gyro"
        case deviceMotion = "motion"

        var description: String {
            switch self {
            case .accelerometer: return "加速度"
            case .gyroscope: return "ジャイロ"
            case .deviceMotion: return "デバイスモーション"
            }
        }
    }

    private var enabledSensors: Set<SensorType> = [.accelerometer]
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

    func start(rateHz: Int, sensors: Set<SensorType>? = nil) {
        guard !isRunning else { return }

        if let sensors = sensors {
            enabledSensors = sensors
        }

        currentRateHz = rateHz
        isRunning = true
        buffer.removeAll()
        totalSamples = 0
        lastError = nil

        let updateInterval = 1.0 / Double(rateHz)

        // 加速度センサー
        if enabledSensors.contains(.accelerometer) && motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = updateInterval
            motionManager.startAccelerometerUpdates()
        }

        // ジャイロスコープ
        if enabledSensors.contains(.gyroscope) && motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = updateInterval
            motionManager.startGyroUpdates()
        }

        // デバイスモーション（姿勢推定）
        if enabledSensors.contains(.deviceMotion) && motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self else { return }

                if let error = error {
                    self.lastError = error.localizedDescription
                    print("DeviceMotion error: \(error)")
                    self.sendErrorToPhone("DeviceMotion error: \(error.localizedDescription)")
                    return
                }

                guard let motion = motion else { return }

                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

                // 全センサーデータを統合
                let accelData = self.motionManager.accelerometerData
                let gyroData = self.motionManager.gyroData

                let sample = (
                    t: timestamp,
                    ax: accelData?.acceleration.x ?? motion.userAcceleration.x,
                    ay: accelData?.acceleration.y ?? motion.userAcceleration.y,
                    az: accelData?.acceleration.z ?? motion.userAcceleration.z,
                    gx: gyroData?.rotationRate.x ?? motion.rotationRate.x,
                    gy: gyroData?.rotationRate.y ?? motion.rotationRate.y,
                    gz: gyroData?.rotationRate.z ?? motion.rotationRate.z,
                    pitch: motion.attitude.pitch,
                    roll: motion.attitude.roll,
                    yaw: motion.attitude.yaw,
                    qx: motion.attitude.quaternion.x,
                    qy: motion.attitude.quaternion.y,
                    qz: motion.attitude.quaternion.z,
                    qw: motion.attitude.quaternion.w
                )

                self.bufferLock.lock()
                // バッファオーバーフロー保護
                if self.buffer.count >= self.maxBufferSize {
                    // 緊急フラッシュ
                    let samplesToSave = self.buffer
                    self.buffer.removeAll()
                    self.bufferLock.unlock()
                    DispatchQueue.global().async {
                        self.saveToTempFile(samplesToSave)
                    }
                } else {
                    self.buffer.append(sample)
                    self.totalSamples += 1
                    self.bufferLock.unlock()
                }
            }
        } else if enabledSensors.contains(.accelerometer) {
            // 加速度のみの場合（従来の動作）
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self else { return }

                if let error = error {
                    self.lastError = error.localizedDescription
                    print("Accelerometer error: \(error)")
                    self.sendErrorToPhone("Accelerometer error: \(error.localizedDescription)")
                    return
                }

                guard let data = data else { return }

                let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                let sample: (
                    t: Int64,
                    ax: Double, ay: Double, az: Double,
                    gx: Double?, gy: Double?, gz: Double?,
                    pitch: Double?, roll: Double?, yaw: Double?,
                    qx: Double?, qy: Double?, qz: Double?, qw: Double?
                ) = (
                    t: timestamp,
                    ax: data.acceleration.x,
                    ay: data.acceleration.y,
                    az: data.acceleration.z,
                    gx: nil, gy: nil, gz: nil,
                    pitch: nil, roll: nil, yaw: nil,
                    qx: nil, qy: nil, qz: nil, qw: nil
                )

                self.bufferLock.lock()
                // バッファオーバーフロー保護
                if self.buffer.count >= self.maxBufferSize {
                    // 緊急フラッシュ
                    let samplesToSave = self.buffer
                    self.buffer.removeAll()
                    self.bufferLock.unlock()
                    DispatchQueue.global().async {
                        self.saveToTempFile(samplesToSave)
                    }
                } else {
                    self.buffer.append(sample)
                    self.totalSamples += 1
                    self.bufferLock.unlock()
                }
            }
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
        motionManager.stopGyroUpdates()
        motionManager.stopDeviceMotionUpdates()
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

    private func sendSamplesToPhone(_ samples: [(
        t: Int64,
        ax: Double, ay: Double, az: Double,
        gx: Double?, gy: Double?, gz: Double?,
        pitch: Double?, roll: Double?, yaw: Double?,
        qx: Double?, qy: Double?, qz: Double?, qw: Double?
    )]) {
        // サンプルを辞書形式に変換
        let samplesArray = samples.map { sample in
            var dict: [String: Any] = [
                "t": sample.t,
                "ax": sample.ax,
                "ay": sample.ay,
                "az": sample.az
            ]

            // オプショナルなデータを追加
            if let gx = sample.gx { dict["gx"] = gx }
            if let gy = sample.gy { dict["gy"] = gy }
            if let gz = sample.gz { dict["gz"] = gz }
            if let pitch = sample.pitch { dict["pitch"] = pitch }
            if let roll = sample.roll { dict["roll"] = roll }
            if let yaw = sample.yaw { dict["yaw"] = yaw }
            if let qx = sample.qx { dict["qx"] = qx }
            if let qy = sample.qy { dict["qy"] = qy }
            if let qz = sample.qz { dict["qz"] = qz }
            if let qw = sample.qw { dict["qw"] = qw }

            return dict
        }

        let message: [String: Any] = [
            "type": "sensor_data",
            "sensors": Array(enabledSensors.map { $0.rawValue }),
            "samples": samplesArray
        ]

        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send samples: \(error)")
            // 送信失敗時は一時ファイルに保存
            self.saveToTempFile(samples)
        }
    }

    private func saveToTempFile(_ samples: [(
        t: Int64,
        ax: Double, ay: Double, az: Double,
        gx: Double?, gy: Double?, gz: Double?,
        pitch: Double?, roll: Double?, yaw: Double?,
        qx: Double?, qy: Double?, qz: Double?, qw: Double?
    )]) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = "tmp_accel_\(timestamp).jsonl"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        var jsonLines = ""
        for sample in samples {
            var json: [String: Any] = [
                "t": sample.t,
                "ax": sample.ax,
                "ay": sample.ay,
                "az": sample.az
            ]

            // オプショナルなデータを追加
            if let gx = sample.gx { json["gx"] = gx }
            if let gy = sample.gy { json["gy"] = gy }
            if let gz = sample.gz { json["gz"] = gz }
            if let pitch = sample.pitch { json["pitch"] = pitch }
            if let roll = sample.roll { json["roll"] = roll }
            if let yaw = sample.yaw { json["yaw"] = yaw }
            if let qx = sample.qx { json["qx"] = qx }
            if let qy = sample.qy { json["qy"] = qy }
            if let qz = sample.qz { json["qz"] = qz }
            if let qw = sample.qw { json["qw"] = qw }

            if let data = try? JSONSerialization.data(withJSONObject: json),
               let line = String(data: data, encoding: .utf8) {
                jsonLines += line + "\n"
            }
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                // ファイルが存在する場合は追記
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer { try? fileHandle.close() } // 新しいAPI: close()を使用

                try fileHandle.seekToEnd()
                if let data = jsonLines.data(using: .utf8) {
                    try fileHandle.write(contentsOf: data)
                }
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

            // ファイルサイズチェック（watchOS制限: 最大50MB）
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                if fileSize > 50_000_000 { // 50MB制限
                    print("File too large for transfer: \(fileSize) bytes")
                    lastError = "File \(fileURL.lastPathComponent) too large (\(fileSize / 1_000_000)MB)"
                    // 大きすぎるファイルは削除またはスキップ
                    pendingFiles.removeAll { $0 == fileURL }
                    try? fileManager.removeItem(at: fileURL) // オプション: 削除
                    continue
                }
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

    private func sendErrorToPhone(_ errorMessage: String) {
        let message: [String: Any] = [
            "type": "sensor_error",
            "error": errorMessage,
            "timestamp": Date().timeIntervalSince1970
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
                var sensors: Set<SensorType> = [.accelerometer]
                if let sensorNames = message["sensors"] as? [String] {
                    sensors = Set(sensorNames.compactMap { SensorType(rawValue: $0) })
                }
                self.start(rateHz: rateHz, sensors: sensors)

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
        if applicationContext["cmd"] != nil {
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