import Foundation
import WatchConnectivity
import Combine

// センサーログ保存マネージャー
final class SensorLogManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SensorLogManager()

    @Published var isLogging: Bool = false
    @Published var currentLogSize: Int64 = 0
    @Published var lastSampleTime: Date?
    @Published var sampleCount: Int = 0

    private let session: WCSession = WCSession.default
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var logDirectory: URL { documentsURL.appendingPathComponent("SensorLogs") }
    private let csvDateFormatter: DateFormatter
    private var fileHandle: FileHandle?
    private var currentDate: String = ""

    private override init() {
        self.csvDateFormatter = DateFormatter()
        self.csvDateFormatter.dateFormat = "yyyyMMdd"
        self.csvDateFormatter.timeZone = TimeZone.current

        super.init()
        ensureLogDirectory()
    }

    // MARK: - Public Methods

    func startSessionIfNeeded() {
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    func currentCSVURLForToday() -> URL {
        let dateString = csvDateFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("accelerometer_\(dateString).csv")
    }

    func exportURLsForToday() -> [URL] {
        let url = currentCSVURLForToday()
        if FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        return []
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

    private func handleIncomingSamples(_ samples: [[Any]]) {
        let url = currentCSVURLForToday()
        let dateString = csvDateFormatter.string(from: Date())

        // 日付が変わったらファイルハンドルを更新
        if currentDate != dateString {
            fileHandle?.closeFile()
            fileHandle = nil
            currentDate = dateString
        }

        // ファイルが存在しない場合はヘッダーを書き込み
        let needsHeader = !FileManager.default.fileExists(atPath: url.path)

        if needsHeader {
            let header = "timestamp_ms,ax,ay,az\n"
            do {
                try header.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write CSV header: \(error)")
                return
            }
        }

        // ファイルハンドルを取得または作成
        if fileHandle == nil {
            do {
                fileHandle = try FileHandle(forWritingTo: url)
                fileHandle?.seekToEndOfFile()
            } catch {
                print("Failed to open file handle: \(error)")
                return
            }
        }

        // サンプルをCSV形式に変換して追記
        var csvLines = ""
        for sample in samples {
            guard sample.count >= 4,
                  let timestamp = sample[0] as? Int64,
                  let ax = sample[1] as? Double,
                  let ay = sample[2] as? Double,
                  let az = sample[3] as? Double else { continue }

            csvLines += "\(timestamp),\(ax),\(ay),\(az)\n"
            sampleCount += 1
        }

        if !csvLines.isEmpty {
            if let data = csvLines.data(using: .utf8) {
                fileHandle?.write(data)
                lastSampleTime = Date()

                // ファイルサイズを更新
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    currentLogSize = attributes[.size] as? Int64 ?? 0
                } catch {
                    print("Failed to get file size: \(error)")
                }
            }
        }
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
                handleIncomingSamples(samples)
            }

            // 処理完了後、一時ファイルを削除
            try FileManager.default.removeItem(at: url)

        } catch {
            print("Failed to process JSONL file: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error)")
        } else {
            print("WCSession activated with state: \(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        // Reactivate session
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Received message from Watch: \(message)")

        // 加速度データの処理
        if let type = message["type"] as? String, type == "accel",
           let samples = message["samples"] as? [[Any]] {
            DispatchQueue.main.async {
                self.handleIncomingSamples(samples)
                self.isLogging = true
            }
        }

        // ステータスメッセージの処理
        if let status = message["status"] as? String {
            DispatchQueue.main.async {
                self.isLogging = (status == "logging")
            }
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        print("Received file from Watch: \(file.fileURL)")

        // JSONLファイルの処理
        if file.fileURL.lastPathComponent.contains("accel") &&
           file.fileURL.pathExtension == "jsonl" {
            handleIncomingJSONLFile(at: file.fileURL)
        }
    }

    // MARK: - Cleanup

    deinit {
        fileHandle?.closeFile()
    }
}