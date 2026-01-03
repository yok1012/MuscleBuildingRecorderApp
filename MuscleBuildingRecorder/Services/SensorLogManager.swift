import Foundation
import WatchConnectivity
import Combine

// センサーログ保存マネージャー
// 注意: WCSessionDelegateはWatchConnectivityServiceが担当。
// センサーデータはWatchConnectivityServiceから転送される。
final class SensorLogManager: NSObject, ObservableObject {
    static let shared = SensorLogManager()

    @Published var isLogging: Bool = false
    @Published var currentLogSize: Int64 = 0
    @Published var lastSampleTime: Date?
    @Published var sampleCount: Int = 0
    @Published var enabledSensors: Set<String> = ["accel"]
    @Published var currentFileType: FileType = .accelerometer
    @Published var recentSamples: [(timestamp: Date, ax: Double, ay: Double, az: Double, gx: Double?, gy: Double?, gz: Double?)] = []
    private let maxRecentSamples = 100  // メモリ管理：最新100サンプルのみ保持
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    var logDirectory: URL { documentsURL.appendingPathComponent("SensorLogs") }
    private let csvDateFormatter: DateFormatter
    private var fileHandles: [FileType: FileHandle] = [:]
    private var currentDate: String = ""

    enum FileType: String, CaseIterable {
        case accelerometer = "accelerometer"
        case gyroscope = "gyroscope"
        case motion = "motion"
        case combined = "combined"

        var csvHeader: String {
            switch self {
            case .accelerometer:
                return "timestamp_ms,ax,ay,az"
            case .gyroscope:
                return "timestamp_ms,gx,gy,gz"
            case .motion:
                return "timestamp_ms,pitch,roll,yaw,qx,qy,qz,qw"
            case .combined:
                return "timestamp_ms,ax,ay,az,gx,gy,gz,pitch,roll,yaw,qx,qy,qz,qw"
            }
        }
    }

    private override init() {
        self.csvDateFormatter = DateFormatter()
        self.csvDateFormatter.dateFormat = "yyyyMMdd"
        self.csvDateFormatter.timeZone = TimeZone.current

        super.init()
        ensureLogDirectory()
    }

    // MARK: - Public Methods

    /// WatchConnectivityServiceから呼び出される：センサーデータの処理
    func processSensorData(samples: [[String: Any]], sensors: [String]) {
        DispatchQueue.main.async {
            self.handleIncomingSamples(samples, sensors: sensors)
            self.isLogging = true
            self.enabledSensors = Set(sensors)
        }
    }

    /// WatchConnectivityServiceから呼び出される：JSOLNファイルの処理
    func processJSONLFile(at url: URL) {
        handleIncomingJSONLFile(at: url)
    }

    /// ステータス更新
    func updateLoggingStatus(_ status: String) {
        DispatchQueue.main.async {
            self.isLogging = (status == "logging")
        }
    }

    func currentCSVURLForToday(type: FileType = .accelerometer) -> URL {
        let dateString = csvDateFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("\(type.rawValue)_\(dateString).csv")
    }

    func exportURLsForToday() -> [URL] {
        var urls: [URL] = []
        let dateString = csvDateFormatter.string(from: Date())

        for type in FileType.allCases {
            let url = logDirectory.appendingPathComponent("\(type.rawValue)_\(dateString).csv")
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        return urls
    }

    func exportDataForToday() -> String? {
        let url = currentCSVURLForToday()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("Failed to read CSV file: \(error)")
            return nil
        }
    }

    func getAllLogFiles() -> [URL] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: .skipsHiddenFiles
            )
            return files.filter { $0.pathExtension == "csv" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        } catch {
            print("Failed to list log files: \(error)")
            return []
        }
    }

    func deleteLogFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete log file: \(error)")
        }
    }

    // MARK: - Private Methods

    private func ensureLogDirectory() {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: logDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                print("Failed to create log directory: \(error)")
            }
        }
    }

    private func handleIncomingSamples(_ samples: [[String: Any]], sensors: [String]) {
        let dateString = csvDateFormatter.string(from: Date())

        // 日付が変わったらファイルハンドルを更新
        if currentDate != dateString {
            for handle in fileHandles.values {
                try? handle.close()  // 新しいAPI: close()を使用
            }
            fileHandles.removeAll()
            currentDate = dateString
        }

        // センサータイプに応じて適切なファイルに書き込み

        for sample in samples {
            guard let timestamp = sample["t"] as? Int64 else { continue }

            // リアルタイム表示用にサンプルを追加
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
            let graphSample = (
                timestamp: date,
                ax: sample["ax"] as? Double ?? 0,
                ay: sample["ay"] as? Double ?? 0,
                az: sample["az"] as? Double ?? 0,
                gx: sample["gx"] as? Double,
                gy: sample["gy"] as? Double,
                gz: sample["gz"] as? Double
            )
            recentSamples.append(graphSample)
            if recentSamples.count > maxRecentSamples {  // メモリリーク防止
                recentSamples.removeFirst()
            }

            // 加速度データ
            if let ax = sample["ax"] as? Double,
               let ay = sample["ay"] as? Double,
               let az = sample["az"] as? Double {
                writeToCSV(type: .accelerometer, line: "\(timestamp),\(ax),\(ay),\(az)\n")
            }

            // ジャイロデータ
            if let gx = sample["gx"] as? Double,
               let gy = sample["gy"] as? Double,
               let gz = sample["gz"] as? Double {
                writeToCSV(type: .gyroscope, line: "\(timestamp),\(gx),\(gy),\(gz)\n")
            }

            // モーションデータ
            if let pitch = sample["pitch"] as? Double,
               let roll = sample["roll"] as? Double,
               let yaw = sample["yaw"] as? Double,
               let qx = sample["qx"] as? Double,
               let qy = sample["qy"] as? Double,
               let qz = sample["qz"] as? Double,
               let qw = sample["qw"] as? Double {
                writeToCSV(type: .motion, line: "\(timestamp),\(pitch),\(roll),\(yaw),\(qx),\(qy),\(qz),\(qw)\n")
            }

            // 統合データ
            if sensors.contains("motion") {
                var line = "\(timestamp)"
                line += ",\(sample["ax"] as? Double ?? 0)"
                line += ",\(sample["ay"] as? Double ?? 0)"
                line += ",\(sample["az"] as? Double ?? 0)"
                line += ",\(sample["gx"] as? Double ?? 0)"
                line += ",\(sample["gy"] as? Double ?? 0)"
                line += ",\(sample["gz"] as? Double ?? 0)"
                line += ",\(sample["pitch"] as? Double ?? 0)"
                line += ",\(sample["roll"] as? Double ?? 0)"
                line += ",\(sample["yaw"] as? Double ?? 0)"
                line += ",\(sample["qx"] as? Double ?? 0)"
                line += ",\(sample["qy"] as? Double ?? 0)"
                line += ",\(sample["qz"] as? Double ?? 0)"
                line += ",\(sample["qw"] as? Double ?? 0)\n"
                writeToCSV(type: .combined, line: line)
            }

            sampleCount += 1
        }

        lastSampleTime = Date()
        updateFileSize()
    }

    private func writeToCSV(type: FileType, line: String) {
        let url = currentCSVURLForToday(type: type)

        // ファイルが存在しない場合はヘッダーを書き込み
        if !FileManager.default.fileExists(atPath: url.path) {
            let header = type.csvHeader + "\n"
            do {
                try header.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write CSV header for \(type): \(error)")
                return
            }
        }

        // ファイルハンドルを取得または作成
        if fileHandles[type] == nil {
            do {
                fileHandles[type] = try FileHandle(forWritingTo: url)
                try? fileHandles[type]?.seekToEnd()  // 新しいAPI: seekToEnd()を使用
            } catch {
                print("Failed to open file handle for \(type): \(error)")
                return
            }
        }

        // データを追記
        if let data = line.data(using: .utf8) {
            do {
                try fileHandles[type]?.write(contentsOf: data)  // 新しいAPI: write(contentsOf:)を使用
            } catch {
                print("Failed to write data for \(type): \(error)")
            }
        }
    }

    private func updateFileSize() {
        var totalSize: Int64 = 0
        for type in FileType.allCases {
            let url = currentCSVURLForToday(type: type)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        currentLogSize = totalSize
    }

    private func handleIncomingJSONLFile(at url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            var samples: [[Any]] = []

            for line in lines {
                guard !line.isEmpty else { continue }

                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let t = json["t"] as? Int64,
                   let ax = json["ax"] as? Double,
                   let ay = json["ay"] as? Double,
                   let az = json["az"] as? Double {
                    samples.append([t, ax, ay, az])
                }
            }

            if !samples.isEmpty {
                // 旧形式のサンプルを新形式に変換
                let convertedSamples = samples.compactMap { sample -> [String: Any]? in
                    guard sample.count >= 4,
                          let t = sample[0] as? Int64,
                          let ax = sample[1] as? Double,
                          let ay = sample[2] as? Double,
                          let az = sample[3] as? Double else { return nil }
                    return ["t": t, "ax": ax, "ay": ay, "az": az]
                }
                handleIncomingSamples(convertedSamples, sensors: ["accel"])
            }

            // 処理完了後、一時ファイルを削除
            try FileManager.default.removeItem(at: url)

        } catch {
            print("Failed to process JSONL file: \(error)")
        }
    }

    // MARK: - Cleanup

    deinit {
        for handle in fileHandles.values {
            try? handle.close()  // 新しいAPI: close()を使用
        }
    }
}