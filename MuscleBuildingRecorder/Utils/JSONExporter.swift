//
//  JSONExporter.swift (V2)
//  MuscleBuildingRecorder
//
//  V2 構造化エクスポート。V1 はこのファイルでは保持しない（完全置換）。
//
//  Output structure:
//    - exportFormatVersion / exportedAt
//    - sessions[]
//        - meta: id, startedAt, endedAt, totalWorkSec, totalRestSec, totalDurationSec, totalVolume, weightUnit
//        - exercises[] (種目ごとに sets[] / restAfterSet[] をネスト)
//            - name, category, totalSets
//            - sets[] (work フェーズ): cycleIndex, startAt, endAt, durationSec, load + loadUnit, reps + repsUnit, heartRate(再計算)
//            - rests[] (work セットの直後の休憩): afterCycleIndex, startAt, endAt, durationSec, heartRate(再計算)
//        - notes[] (時系列の独立イベント。SetRecord.note の累積は廃止)
//        - heartRateTimeSeries[] (オプション: with-statistics モードのみ含める)
//        - statistics
//    - overallStatistics (with-statistics モードのみ)
//
//  心拍データはセット範囲で `HeartRateCSVLogger.computeStats(from:to:)` を用いて再計算する。
//  メモは過去 SetRecord.note があれば 1 件として変換、新規データは WorkoutNoteLogger から拾う。
//

import Foundation
import CoreData

class JSONExporter {

    // MARK: - Public API（既存呼び出し互換）

    static func export(sessions: [Session]) -> String {
        encode(makePayload(sessions: sessions, includeTimeSeries: false, includeOverall: false))
    }

    static func exportSingleSession(_ session: Session) -> String {
        let payload = SessionPayload(session: session, includeTimeSeries: false)
        return encode(payload)
    }

    static func exportWithStatistics(sessions: [Session]) -> String {
        encode(makePayload(sessions: sessions, includeTimeSeries: true, includeOverall: true))
    }

    // MARK: - Build payload

    private static func makePayload(
        sessions: [Session],
        includeTimeSeries: Bool,
        includeOverall: Bool
    ) -> ExportPayload {
        let sessionPayloads = sessions.map { SessionPayload(session: $0, includeTimeSeries: includeTimeSeries) }
        return ExportPayload(
            exportFormatVersion: "2.1",  // 2.1: ドメイン（workout/study/work）情報を追加
            exportedAt: Date(),
            sessions: sessionPayloads,
            overallStatistics: includeOverall ? OverallStatistics(from: sessions) : nil
        )
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("JSONExporter: encode failed: \(error)")
            return "{\"error\":\"encode failed\",\"message\":\"\(error.localizedDescription)\"}"
        }
    }
}

// MARK: - Top-level payload

private struct ExportPayload: Codable {
    let exportFormatVersion: String
    let exportedAt: Date
    let sessions: [SessionPayload]
    let overallStatistics: OverallStatistics?
}

// MARK: - Session payload

private struct SessionPayload: Codable {
    let id: String
    let domain: String                    // V2.1: workout / study / work
    let title: String?                    // V2.1: study/work のセッションタイトル
    let subjectOrProject: String?         // V2.1: study=科目, work=プロジェクト
    let startedAt: Date?
    let endedAt: Date?
    let totalWorkSec: Int
    let totalRestSec: Int
    let totalDurationSec: Int
    let totalVolume: Double
    let weightUnit: String
    let exercises: [ExercisePayload]
    let notes: [NotePayload]
    let heartRateTimeSeries: [HeartRateSamplePayload]?
    let statistics: SessionStatistics

    init(session: Session, includeTimeSeries: Bool) {
        self.id = session.id?.uuidString ?? ""
        self.domain = session.domainEnum.rawValue
        self.title = session.title
        self.subjectOrProject = session.subjectOrProject
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.totalWorkSec = Int(session.totalWorkSec)
        self.totalRestSec = Int(session.totalRestSec)
        self.totalDurationSec = Int(session.totalWorkSec + session.totalRestSec)
        self.totalVolume = session.totalVolume

        let setRecords: [SetRecord] = (session.setRecords?.allObjects as? [SetRecord]) ?? []
        let sortedRecords = setRecords.sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }

        self.exercises = ExercisePayload.build(from: sortedRecords)
        self.weightUnit = SessionPayload.dominantWeightUnit(from: sortedRecords)
        self.statistics = SessionStatistics(records: sortedRecords)

        // メモ：WorkoutNoteLogger（時系列） + 過去 SetRecord.note の互換変換
        let rangeStart = session.startedAt ?? sortedRecords.first?.startAt ?? Date.distantPast
        let rangeEnd = session.endedAt ?? sortedRecords.last?.endAt ?? Date()
        var combinedNotes = WorkoutNoteLogger.shared
            .loadEntries(from: rangeStart, to: rangeEnd)
            .map { NotePayload(entry: $0, exercises: sortedRecords) }
        // 過去 SetRecord.note（V1 で書かれた累積データ）も 1 件ずつ変換し、
        // 既に WorkoutNoteLogger 側に入っているテキストと一致するものは除外
        let existingTexts = Set(combinedNotes.map { $0.text })
        for record in sortedRecords {
            guard let raw = record.note?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  !existingTexts.contains(raw),
                  let ts = record.startAt
            else { continue }
            combinedNotes.append(NotePayload(
                timestamp: ts,
                phase: record.phase ?? "",
                cycleIndex: Int(record.cycleIndex),
                exercise: record.name ?? "",
                category: record.category ?? "",
                text: raw,
                heartRateAtTime: 0
            ))
        }
        self.notes = combinedNotes.sorted { $0.timestamp < $1.timestamp }

        // 時系列心拍（with-statistics のみ）
        if includeTimeSeries, let s = session.startedAt, let e = session.endedAt {
            self.heartRateTimeSeries = HeartRateCSVLogger.shared
                .loadSamples(from: s, to: e)
                .map { HeartRateSamplePayload(sample: $0) }
        } else {
            self.heartRateTimeSeries = nil
        }
    }

    /// 種目から優位な weightUnit を抽出。混在は "mixed"
    private static func dominantWeightUnit(from records: [SetRecord]) -> String {
        let context = DataController.shared.container.viewContext
        var units = Set<String>()
        for record in records where record.phase == "Work" {
            guard let name = record.name, !name.isEmpty else { continue }
            let request: NSFetchRequest<ExerciseMaster> = ExerciseMaster.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", name)
            request.fetchLimit = 1
            if let m = try? context.fetch(request).first, let u = m.loadUnit, !u.isEmpty {
                units.insert(u)
            }
        }
        if units.isEmpty { return "kg" }
        if units.count == 1 { return units.first! }
        return "mixed"
    }
}

// MARK: - Exercise / sets / rests

private struct ExercisePayload: Codable {
    let name: String
    let category: String
    let totalSets: Int
    let sets: [SetPayload]
    let rests: [RestPayload]

    static func build(from sortedRecords: [SetRecord]) -> [ExercisePayload] {
        // 種目（category, name の組）ごとに work / rest をグルーピングし、
        // セット完了直後の rest を「直前 work cycleIndex の休憩」として紐付ける。
        struct Key: Hashable { let category: String; let name: String }
        var ordered: [Key] = []
        var groups: [Key: (sets: [SetRecord], rests: [(afterCycleIndex: Int, record: SetRecord)])] = [:]

        var lastWorkKey: Key?
        var lastWorkCycle: Int?

        for record in sortedRecords {
            let key = Key(category: record.category ?? "", name: record.name ?? "")
            if record.phase == "Work" {
                if groups[key] == nil {
                    ordered.append(key)
                    groups[key] = (sets: [], rests: [])
                }
                groups[key]?.sets.append(record)
                lastWorkKey = key
                lastWorkCycle = Int(record.cycleIndex)
            } else if record.phase == "Rest" {
                // Rest は直前の Work と同じ種目に紐付ける
                if let k = lastWorkKey, let cy = lastWorkCycle {
                    groups[k]?.rests.append((afterCycleIndex: cy, record: record))
                }
            }
        }

        return ordered.compactMap { key in
            guard let g = groups[key] else { return nil }
            let sets = g.sets.map { SetPayload(record: $0) }
            let rests = g.rests.map { RestPayload(afterCycleIndex: $0.afterCycleIndex, record: $0.record) }
            return ExercisePayload(
                name: key.name,
                category: key.category,
                totalSets: sets.count,
                sets: sets,
                rests: rests
            )
        }
    }
}

private struct SetPayload: Codable {
    let cycleIndex: Int
    let startAt: Date?
    let endAt: Date?
    let durationSec: Int?
    let load: Double
    let loadUnit: String
    let reps: Double
    let repsUnit: String
    let taskName: String?     // V2.1: study/work でタスク名を保持
    let heartRate: HeartRateStatsPayload

    init(record: SetRecord) {
        self.cycleIndex = Int(record.cycleIndex)
        self.startAt = record.startAt
        self.endAt = record.endAt
        if let s = record.startAt, let e = record.endAt {
            self.durationSec = Int(e.timeIntervalSince(s))
        } else { self.durationSec = nil }
        self.load = record.load
        self.reps = record.reps
        let masterUnits = SetPayload.lookupUnits(name: record.name)
        self.loadUnit = masterUnits.load
        self.repsUnit = masterUnits.reps
        self.taskName = record.taskName
        self.heartRate = HeartRateStatsPayload(forRange: record.startAt, end: record.endAt, fallback: record)
    }

    private static func lookupUnits(name: String?) -> (load: String, reps: String) {
        guard let name, !name.isEmpty else { return ("kg", "回") }
        let request: NSFetchRequest<ExerciseMaster> = ExerciseMaster.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", name)
        request.fetchLimit = 1
        if let m = try? DataController.shared.container.viewContext.fetch(request).first {
            return (m.loadUnit ?? "kg", m.repsUnit ?? "回")
        }
        return ("kg", "回")
    }
}

private struct RestPayload: Codable {
    let afterCycleIndex: Int
    let startAt: Date?
    let endAt: Date?
    let durationSec: Int?
    let heartRate: HeartRateStatsPayload

    init(afterCycleIndex: Int, record: SetRecord) {
        self.afterCycleIndex = afterCycleIndex
        self.startAt = record.startAt
        self.endAt = record.endAt
        if let s = record.startAt, let e = record.endAt {
            self.durationSec = Int(e.timeIntervalSince(s))
        } else { self.durationSec = nil }
        self.heartRate = HeartRateStatsPayload(forRange: record.startAt, end: record.endAt, fallback: record)
    }
}

// MARK: - Heart rate

private struct HeartRateStatsPayload: Codable {
    let avg: Double
    let max: Double
    let min: Double
    let slope: Double
    let sampleCount: Int

    /// セット範囲があれば CSV から再計算、なければ SetRecord 保存値にフォールバック
    init(forRange start: Date?, end: Date?, fallback record: SetRecord) {
        if let s = start, let e = end,
           let stats = HeartRateCSVLogger.shared.computeStats(from: s, to: e) {
            self.avg = stats.avg
            self.max = stats.max
            self.min = stats.min
            self.slope = stats.slope
            self.sampleCount = stats.sampleCount
        } else {
            self.avg = record.hrAvg
            self.max = record.hrMax
            self.min = record.hrMin
            self.slope = record.hrSlopeAvg
            self.sampleCount = 0
        }
    }
}

private struct HeartRateSamplePayload: Codable {
    let timestamp: Date
    let bpm: Double
    let phase: String
    let cycleIndex: Int

    init(sample: HeartRateCSVLogger.Sample) {
        self.timestamp = sample.timestamp
        self.bpm = sample.bpm
        self.phase = sample.phase
        self.cycleIndex = sample.cycleIndex
    }
}

// MARK: - Notes

private struct NotePayload: Codable {
    let timestamp: Date
    let phase: String
    let cycleIndex: Int
    let exercise: String
    let category: String
    let text: String
    let heartRateAtTime: Double

    init(timestamp: Date, phase: String, cycleIndex: Int, exercise: String, category: String, text: String, heartRateAtTime: Double) {
        self.timestamp = timestamp
        self.phase = phase
        self.cycleIndex = cycleIndex
        self.exercise = exercise
        self.category = category
        self.text = text
        self.heartRateAtTime = heartRateAtTime
    }

    /// WorkoutNoteEntry から構築。timestamp に対応する SetRecord（Work）を見て exercise/category を補完
    init(entry: WorkoutNoteEntry, exercises records: [SetRecord]) {
        self.timestamp = entry.timestamp
        self.phase = entry.phase
        self.cycleIndex = entry.cycleIndex
        self.text = entry.text
        self.heartRateAtTime = entry.heartRate

        // timestamp が含まれる Work record から exercise/category を引く
        if let r = records.first(where: {
            guard let s = $0.startAt else { return false }
            let e = $0.endAt ?? Date()
            return entry.timestamp >= s && entry.timestamp <= e
        }) {
            self.exercise = r.name ?? ""
            self.category = r.category ?? ""
        } else {
            self.exercise = ""
            self.category = ""
        }
    }
}

// MARK: - Statistics

private struct SessionStatistics: Codable {
    let avgHeartRate: Double
    let maxHeartRate: Double
    let minHeartRate: Double
    let workSets: Int
    let restSets: Int
    let categories: [String]
    let exercises: [String]

    init(records: [SetRecord]) {
        let workOnly = records.filter { $0.phase == "Work" }
        // セットごとに CSV から再計算した値を集計
        var avgs: [Double] = []
        var maxs: [Double] = []
        var mins: [Double] = []
        for r in workOnly {
            guard let s = r.startAt, let e = r.endAt,
                  let stats = HeartRateCSVLogger.shared.computeStats(from: s, to: e) else { continue }
            avgs.append(stats.avg)
            maxs.append(stats.max)
            mins.append(stats.min)
        }
        self.avgHeartRate = avgs.isEmpty ? 0 : avgs.reduce(0, +) / Double(avgs.count)
        self.maxHeartRate = maxs.max() ?? 0
        self.minHeartRate = mins.filter { $0 > 0 }.min() ?? 0
        self.workSets = records.filter { $0.phase == "Work" }.count
        self.restSets = records.filter { $0.phase == "Rest" }.count
        self.categories = Array(Set(records.compactMap { $0.category }.filter { !$0.isEmpty })).sorted()
        self.exercises = Array(Set(records.compactMap { $0.name }.filter { !$0.isEmpty })).sorted()
    }
}

private struct OverallStatistics: Codable {
    let totalSessions: Int
    let totalWorkoutSec: Int
    let totalVolume: Double
    let avgSessionDurationSec: Double
    let uniqueExercises: Int

    init(from sessions: [Session]) {
        self.totalSessions = sessions.count
        let totalSec = sessions.reduce(0) { $0 + Int($1.totalWorkSec + $1.totalRestSec) }
        self.totalWorkoutSec = totalSec
        self.totalVolume = sessions.reduce(0) { $0 + $1.totalVolume }
        self.avgSessionDurationSec = sessions.isEmpty ? 0 : Double(totalSec) / Double(sessions.count)
        var names = Set<String>()
        for s in sessions {
            if let recs = s.setRecords?.allObjects as? [SetRecord] {
                for r in recs where r.phase == "Work" {
                    if let n = r.name, !n.isEmpty { names.insert(n) }
                }
            }
        }
        self.uniqueExercises = names.count
    }
}
