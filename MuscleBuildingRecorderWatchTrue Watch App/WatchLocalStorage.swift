#if os(watchOS)
import Foundation

// MARK: - Workout Session Data Model
/// Watch単独ワークアウト時のセッションデータ
struct WorkoutSessionData: Codable {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var currentPhase: String
    var cycleIndex: Int
    var totalWorkTime: TimeInterval
    var totalRestTime: TimeInterval
    var elapsedTime: TimeInterval
    var heartRateSamples: [HeartRateSampleData]
    var isCompleted: Bool

    init(startTime: Date = Date()) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = nil
        self.currentPhase = "work"
        self.cycleIndex = 0
        self.totalWorkTime = 0
        self.totalRestTime = 0
        self.elapsedTime = 0
        self.heartRateSamples = []
        self.isCompleted = false
    }
}

// MARK: - Heart Rate Sample Data
struct HeartRateSampleData: Codable {
    var timestamp: Date
    var bpm: Double
    var phase: String
}

// MARK: - Sensor Sample Data
struct SensorSampleData: Codable {
    var timestamp: Date
    var accelX: Double?
    var accelY: Double?
    var accelZ: Double?
    var gyroX: Double?
    var gyroY: Double?
    var gyroZ: Double?
}

// MARK: - Watch Local Storage
/// Watch用のローカルデータ永続化マネージャー
class WatchLocalStorage {
    static let shared = WatchLocalStorage()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Keys
    private enum Keys {
        static let currentSession = "watchCurrentSession"
        static let pendingSyncData = "watchPendingSyncData"
        static let pendingSensorData = "watchPendingSensorData"
        static let lastSyncTimestamp = "watchLastSyncTimestamp"
    }

    // MARK: - Limits
    private let maxSensorSamples = 10000  // 約80KB
    private let maxHeartRateSamples = 3600  // 1時間分（1サンプル/秒）

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Current Session Management

    /// ワークアウトセッションを開始
    func startSession() -> WorkoutSessionData {
        let session = WorkoutSessionData()
        saveSession(session)
        print("WatchLocalStorage: New session started with ID: \(session.id)")
        return session
    }

    /// ワークアウトセッションを保存
    func saveSession(_ session: WorkoutSessionData) {
        if let data = try? encoder.encode(session) {
            defaults.set(data, forKey: Keys.currentSession)
            print("WatchLocalStorage: Session saved")
        }
    }

    /// セッションを復元（アプリ再起動時など）
    func restoreSession() -> WorkoutSessionData? {
        guard let data = defaults.data(forKey: Keys.currentSession) else {
            print("WatchLocalStorage: No session to restore")
            return nil
        }

        if let session = try? decoder.decode(WorkoutSessionData.self, from: data) {
            // 完了済みセッションは復元しない
            if session.isCompleted {
                print("WatchLocalStorage: Session found but already completed")
                return nil
            }
            print("WatchLocalStorage: Session restored with ID: \(session.id)")
            return session
        }

        return nil
    }

    /// セッションを終了してマーク
    func completeSession() -> WorkoutSessionData? {
        guard var session = restoreSessionRaw() else { return nil }

        session.endTime = Date()
        session.isCompleted = true
        saveSession(session)

        // 同期待ちデータに追加
        addToPendingSyncData(session)

        print("WatchLocalStorage: Session completed")
        return session
    }

    /// セッションを終了時にクリア
    func clearSession() {
        defaults.removeObject(forKey: Keys.currentSession)
        print("WatchLocalStorage: Session cleared")
    }

    /// 完了/未完了を問わず現在のセッションを取得（内部用）
    private func restoreSessionRaw() -> WorkoutSessionData? {
        guard let data = defaults.data(forKey: Keys.currentSession) else { return nil }
        return try? decoder.decode(WorkoutSessionData.self, from: data)
    }

    // MARK: - Session Update Methods

    /// フェーズを更新
    func updatePhase(_ phase: String, cycleIndex: Int) {
        guard var session = restoreSessionRaw() else { return }
        session.currentPhase = phase
        session.cycleIndex = cycleIndex
        saveSession(session)
    }

    /// 時間を更新
    func updateTimes(totalWorkTime: TimeInterval, totalRestTime: TimeInterval, elapsedTime: TimeInterval) {
        guard var session = restoreSessionRaw() else { return }
        session.totalWorkTime = totalWorkTime
        session.totalRestTime = totalRestTime
        session.elapsedTime = elapsedTime
        saveSession(session)
    }

    /// 心拍数サンプルを追加
    func addHeartRateSample(bpm: Double, phase: String) {
        guard var session = restoreSessionRaw() else { return }

        let sample = HeartRateSampleData(timestamp: Date(), bpm: bpm, phase: phase)
        session.heartRateSamples.append(sample)

        // 最大数を超えたら古いサンプルを削除
        if session.heartRateSamples.count > maxHeartRateSamples {
            session.heartRateSamples.removeFirst(session.heartRateSamples.count - maxHeartRateSamples)
        }

        saveSession(session)
    }

    // MARK: - Pending Sync Data

    /// 同期待ちセッションデータを追加
    private func addToPendingSyncData(_ session: WorkoutSessionData) {
        var pending = loadPendingSyncData()
        pending.append(session)

        if let data = try? encoder.encode(pending) {
            defaults.set(data, forKey: Keys.pendingSyncData)
        }

        print("WatchLocalStorage: Session added to pending sync queue. Total: \(pending.count)")
    }

    /// 同期待ちセッションデータを取得
    func loadPendingSyncData() -> [WorkoutSessionData] {
        guard let data = defaults.data(forKey: Keys.pendingSyncData) else { return [] }
        return (try? decoder.decode([WorkoutSessionData].self, from: data)) ?? []
    }

    /// 同期完了後、セッションデータをクリア
    func clearPendingSyncData() {
        defaults.removeObject(forKey: Keys.pendingSyncData)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncTimestamp)
        print("WatchLocalStorage: Pending sync data cleared")
    }

    /// 特定のセッションを同期待ちから削除
    func removePendingSyncData(sessionId: UUID) {
        var pending = loadPendingSyncData()
        pending.removeAll { $0.id == sessionId }

        if pending.isEmpty {
            defaults.removeObject(forKey: Keys.pendingSyncData)
        } else if let data = try? encoder.encode(pending) {
            defaults.set(data, forKey: Keys.pendingSyncData)
        }

        print("WatchLocalStorage: Session \(sessionId) removed from pending sync queue")
    }

    // MARK: - Sensor Data Management

    /// センサーデータをバッファに保存（通信失敗時）
    func saveSensorDataBatch(_ batch: [SensorSampleData]) {
        var existing = loadPendingSensorData()
        existing.append(contentsOf: batch)

        // 最大サンプル数を超えたら古いデータを削除
        if existing.count > maxSensorSamples {
            existing.removeFirst(existing.count - maxSensorSamples)
        }

        if let data = try? encoder.encode(existing) {
            defaults.set(data, forKey: Keys.pendingSensorData)
        }

        print("WatchLocalStorage: Sensor batch saved. Total samples: \(existing.count)")
    }

    /// 保存されたセンサーデータを取得
    func loadPendingSensorData() -> [SensorSampleData] {
        guard let data = defaults.data(forKey: Keys.pendingSensorData) else { return [] }
        return (try? decoder.decode([SensorSampleData].self, from: data)) ?? []
    }

    /// センサーデータをクリア
    func clearPendingSensorData() {
        defaults.removeObject(forKey: Keys.pendingSensorData)
        print("WatchLocalStorage: Pending sensor data cleared")
    }

    // MARK: - Sync Status

    /// 最後の同期タイムスタンプを取得
    func getLastSyncTimestamp() -> Date? {
        let timestamp = defaults.double(forKey: Keys.lastSyncTimestamp)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    /// 同期待ちデータがあるか確認
    func hasPendingData() -> Bool {
        return !loadPendingSyncData().isEmpty || !loadPendingSensorData().isEmpty
    }

    // MARK: - Debug

    /// デバッグ情報を取得
    func getDebugInfo() -> String {
        let pendingSessions = loadPendingSyncData().count
        let pendingSensors = loadPendingSensorData().count
        let hasCurrentSession = restoreSessionRaw() != nil
        let lastSync = getLastSyncTimestamp()?.description ?? "Never"

        return """
        WatchLocalStorage Debug:
        - Current Session: \(hasCurrentSession ? "Yes" : "No")
        - Pending Sessions: \(pendingSessions)
        - Pending Sensor Samples: \(pendingSensors)
        - Last Sync: \(lastSync)
        """
    }
}
#endif
