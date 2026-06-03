import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct HistoryDetailView: View {
    let session: Session
    @Environment(\.dismiss) var dismiss
    @State private var showingExportOptions = false
    @State private var exportType: ExportType = .csvDetailed
    @State private var exportData: ExportData?
    @State private var showingShareSheet = false
    @State private var showingHeartRateChart = false

    enum ExportType: String, CaseIterable {
        case csvDetailed = "CSV (詳細)"
        case csvSummary = "CSV (サマリー)"
        case jsonNormal = "JSON (通常)"
        case jsonWithHeartRate = "JSON (心拍数ログ付き)"

        var fileExtension: String {
            switch self {
            case .csvDetailed, .csvSummary:
                return "csv"
            case .jsonNormal, .jsonWithHeartRate:
                return "json"
            }
        }

        var contentType: UTType {
            switch self {
            case .csvDetailed, .csvSummary:
                return .commaSeparatedText
            case .jsonNormal, .jsonWithHeartRate:
                return .json
            }
        }
    }

    struct ExportData: Identifiable {
        let id = UUID()
        let content: String
        let filename: String
        let type: UTType
    }

    private var records: [SetRecord] {
        (session.setRecords?.allObjects as? [SetRecord] ?? [])
            .sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }
    }

    /// このセッションの期間内に記録されたメモ
    /// - 主な保存先: `WorkoutNoteLogger` の CSV（「メモを残す」シート経由の独立メモ）
    /// - 補完: `SetRecord.payload.memo`（休憩中インライン入力のクイックメモ）
    ///   こちらは `record.note` に JSON または平文で保存されるため、payload としてデコードして取り出す
    private var sessionNotes: [WorkoutNoteEntry] {
        guard let start = session.startedAt else { return [] }
        let end = session.endedAt ?? Date()
        var entries = WorkoutNoteLogger.shared.loadEntries(from: start, to: end)

        // SetRecord 側の payload.memo を補完（WorkoutNoteLogger 側と重複するテキストは除外）
        let existingTexts = Set(entries.map { $0.text })
        for record in records {
            let memo = record.payload.memo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !memo.isEmpty, !existingTexts.contains(memo) else { continue }
            // タイムスタンプは record.endAt（セット完了時刻）を優先、なければ startAt
            guard let ts = record.endAt ?? record.startAt else { continue }
            entries.append(WorkoutNoteEntry(
                timestamp: ts,
                phase: (record.phase ?? "").lowercased(),
                cycleIndex: Int(record.cycleIndex),
                text: memo,
                heartRate: record.hrAvg
            ))
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    private var dateString: String {
        guard let date = session.startedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private var durationString: String {
        let totalSeconds = Int(session.totalWorkSec + session.totalRestSec)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d分%d秒", minutes, seconds)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // セッション概要カード
                    sessionOverviewCard

                    // 心拍数グラフセクション
                    if !session.allHeartRateLogs.isEmpty {
                        HeartRateChartView(session: session)
                            .onTapGesture {
                                showingHeartRateChart = true
                            }
                    }

                    // エクササイズ詳細
                    exerciseDetailsSection

                    // メモ履歴
                    notesSection

                    // エクスポートボタン
                    exportButtonsSection
                }
                .padding()
            }
            .navigationTitle("ワークアウト詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsSheet(
                    exportType: $exportType,
                    onExport: performExport
                )
            }
            .sheet(item: $exportData) { data in
                ShareSheet(
                    items: [ExportDocument(data: data.content, filename: data.filename, type: data.type)],
                    onComplete: { _ in }
                )
            }
            .sheet(isPresented: $showingHeartRateChart) {
                FullScreenHeartRateChartView(session: session)
            }
        }
    }

    private var sessionOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("セッション概要")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // ドメインバッジ + タイトル（study/work のみ）
                HStack {
                    Label("モード", systemImage: session.domainEnum.iconName)
                        .font(.caption)
                        .foregroundColor(domainAccentColor)
                    Spacer()
                    Text(session.domainEnum.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(domainAccentColor)
                }

                if session.domainEnum != .workout, let title = session.title, !title.isEmpty {
                    HStack {
                        Label("タスク", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                if session.domainEnum != .workout, let subjectOrProject = session.subjectOrProject, !subjectOrProject.isEmpty {
                    HStack {
                        Label(session.domainEnum == .study ? "科目" : "プロジェクト", systemImage: "tag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(subjectOrProject)
                            .font(.caption)
                    }
                }

                HStack {
                    Label("日時", systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(dateString)
                        .font(.caption)
                }

                HStack {
                    Label("合計時間", systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(durationString)
                        .font(.caption)
                }

                HStack {
                    Label("\(session.domainEnum.workPhaseLabel)時間", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Text("\(session.totalWorkSec / 60)分\(session.totalWorkSec % 60)秒")
                        .font(.caption)
                }

                HStack {
                    Label("\(session.domainEnum.restPhaseLabel)時間", systemImage: "pause.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                    Text("\(session.totalRestSec / 60)分\(session.totalRestSec % 60)秒")
                        .font(.caption)
                }

                // 総ボリュームは workout のみ表示（study/work では意味がないため非表示）
                if session.domainEnum == .workout {
                    HStack {
                        Label("総ボリューム", systemImage: "scalemass.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(session.totalVolume, specifier: "%.1f") kg")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                if let stats = session.heartRateStatistics {
                    Divider()
                    HStack {
                        Label("心拍数", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                        Text("最小: \(Int(stats.min)) / 平均: \(Int(stats.avg)) / 最大: \(Int(stats.max)) bpm")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    private var domainAccentColor: Color {
        switch session.domainEnum {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    private var exerciseDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.domainEnum == .workout ? LocalizedStringKey("エクササイズ詳細") : LocalizedStringKey("サイクル詳細"))
                .font(.headline)

            ForEach(records, id: \.self) { record in
                ExerciseRecordCard(record: record, domain: session.domainEnum)
            }
        }
    }

    private var notesSection: some View {
        let notes = sessionNotes
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("メモ")
                    .font(.headline)
                Spacer()
                Text("\(notes.count) 件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if notes.isEmpty {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary)
                    Text("このセッション中のメモはありません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                ForEach(notes) { entry in
                    NoteEntryCard(entry: entry)
                }
            }
        }
    }

    private var exportButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showingExportOptions = true }) {
                Label("このセッションをエクスポート", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            // 心拍数データエクスポート
            HStack(spacing: 12) {
                Button(action: exportHeartRateCSV) {
                    Label("心拍数CSV", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: exportHeartRateJSON) {
                    Label("心拍数JSON", systemImage: "heart.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
    }

    private func performExport() {
        showingExportOptions = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: session.startedAt ?? Date())

        var content = ""
        var filename = ""

        switch exportType {
        case .csvDetailed:
            content = CSVExporter.export(sessions: [session])
            filename = "workout_\(timestamp)_detailed.csv"
        case .csvSummary:
            content = CSVExporter.exportSummary(sessions: [session])
            filename = "workout_\(timestamp)_summary.csv"
        case .jsonNormal:
            content = JSONExporter.exportSingleSession(session)
            filename = "workout_\(timestamp).json"
        case .jsonWithHeartRate:
            content = exportJSONWithHeartRateLogs()
            filename = "workout_\(timestamp)_with_hr.json"
        }

        exportData = ExportData(
            content: content,
            filename: filename,
            type: exportType.contentType
        )
        showingShareSheet = true
    }

    private func exportHeartRateCSV() {
        guard let startDate = session.startedAt else { return }

        let logger = HeartRateCSVLogger.shared
        if let fileURL = logger.getLogFile(for: startDate) {
            exportData = ExportData(
                content: try! String(contentsOf: fileURL, encoding: .utf8),
                filename: fileURL.lastPathComponent,
                type: .commaSeparatedText
            )
        } else {
            print("心拍数CSVファイルが見つかりません")
        }
    }

    private func exportHeartRateJSON() {
        guard let startDate = session.startedAt else { return }

        let logger = HeartRateCSVLogger.shared
        if let jsonData = logger.getLogDataAsJSON(for: startDate),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "heartrate_\(dateFormatter.string(from: startDate)).json"

            exportData = ExportData(
                content: jsonString,
                filename: filename,
                type: .json
            )
        } else {
            print("心拍数JSONデータが見つかりません")
        }
    }

    private func exportJSONWithHeartRateLogs() -> String {
        var sessionData = SessionDataWithHeartRate(from: session)
        if let setRecords = session.setRecords?.allObjects as? [SetRecord] {
            let sortedRecords = setRecords.sorted { ($0.startAt ?? Date.distantPast) < ($1.startAt ?? Date.distantPast) }
            sessionData.records = sortedRecords.map { RecordDataWithHeartRate(from: $0) }
        }
        // 過去のセッションの場合は生成、現在のセッションはログマネージャーから取得
        sessionData.heartRateLogs = session.endedAt != nil ? session.generateHeartRateLogs() : session.allHeartRateLogs

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(sessionData),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }
}

// エクササイズレコードカード（ドメイン別表示）
private struct ExerciseRecordCard: View {
    let record: SetRecord
    let domain: ActivityDomain

    private var durationString: String? {
        guard let start = record.startAt, let end = record.endAt else { return nil }
        let seconds = Int(end.timeIntervalSince(start))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// 主タイトル（workout = カテゴリ-種目、study/work = タスク名）
    private var primaryText: String? {
        switch domain {
        case .workout:
            guard let name = record.name, !name.isEmpty else { return nil }
            return "\(record.category ?? "") - \(name)"
        case .study, .work:
            let taskName = record.taskName ?? ""
            return taskName.isEmpty ? nil : taskName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let phase = record.phase {
                    Text(phase)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(phase == "Work" ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                Text("サイクル \(record.cycleIndex)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if let duration = durationString {
                    Text(duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let primary = primaryText {
                HStack {
                    Text(primary)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    // workout のみ load×reps を表示
                    if domain == .workout, record.load > 0 || record.reps > 0 {
                        Text("\(record.load, specifier: "%.1f") kg × \(Int(record.reps)) 回")
                            .font(.caption)
                    }
                }
            }

            if record.hrAvg > 0 {
                HStack(spacing: 12) {
                    Label("\(Int(record.hrAvg)) bpm", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("最小: \(Int(record.hrMin)) / 最大: \(Int(record.hrMax))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // payload としてデコードし、memo / tags / RPE を分けて表示
            let payload = record.payload
            if !payload.memo.isEmpty {
                Text(payload.memo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            if !payload.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(payload.tags, id: \.self) { tag in
                            Text(tag.localizedSeed)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.25))
                                .foregroundColor(.primary)
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.top, 2)
            }
            // F-2: Physical / Mental RPE 表示
            if payload.rpe != nil || payload.mentalRpe != nil {
                HStack(spacing: 12) {
                    if let p = payload.rpe {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("肉体 \(p)/5")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let m = payload.mentalRpe {
                        HStack(spacing: 3) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            Text("精神 \(m)/5")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// メモエントリーカード
private struct NoteEntryCard: View {
    let entry: WorkoutNoteEntry

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }

    private var phaseDisplay: String {
        switch entry.phase.lowercased() {
        case "work": return "筋トレ".localizedSeed
        case "rest": return "休憩".localizedSeed
        default: return entry.phase
        }
    }

    private var phaseColor: Color {
        switch entry.phase.lowercased() {
        case "work": return .orange
        case "rest": return .blue
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(timeString)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Text(phaseDisplay)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(phaseColor.opacity(0.2))
                    .foregroundColor(phaseColor)
                    .cornerRadius(4)

                Text("サイクル \(entry.cycleIndex)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if entry.heartRate > 0 {
                    Label("\(Int(entry.heartRate))", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            Text(entry.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// エクスポートオプションシート
private struct ExportOptionsSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var exportType: HistoryDetailView.ExportType
    let onExport: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("エクスポート形式を選択")) {
                    ForEach(HistoryDetailView.ExportType.allCases, id: \.self) { type in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(type.rawValue)
                                    .font(.headline)
                                Text(descriptionForType(type))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if exportType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            exportType = type
                        }
                    }
                }

                Section {
                    Button(action: {
                        dismiss()
                        onExport()
                    }) {
                        HStack {
                            Spacer()
                            Text("エクスポート")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("エクスポート設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func descriptionForType(_ type: HistoryDetailView.ExportType) -> String {
        switch type {
        case .csvDetailed:
            return "全セットレコードを含む詳細データ".localizedSeed
        case .csvSummary:
            return "セッション単位のサマリーデータ".localizedSeed
        case .jsonNormal:
            return "構造化されたJSONフォーマット".localizedSeed
        case .jsonWithHeartRate:
            return "心拍数ログを含む完全なデータ".localizedSeed
        }
    }
}

// 心拍数ログ付きのデータ構造
struct SessionDataWithHeartRate: Codable {
    let id: String
    let startedAt: Date?
    let endedAt: Date?
    let totalWorkSec: Int
    let totalRestSec: Int
    let totalVolume: Double
    var records: [RecordDataWithHeartRate] = []
    var heartRateLogs: [HeartRateLogData] = []

    init(from session: Session) {
        self.id = session.id?.uuidString ?? ""
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.totalWorkSec = Int(session.totalWorkSec)
        self.totalRestSec = Int(session.totalRestSec)
        self.totalVolume = session.totalVolume
    }
}

struct RecordDataWithHeartRate: Codable {
    let id: String
    let cycleIndex: Int
    let phase: String
    let startAt: Date?
    let endAt: Date?
    let category: String
    let exercise: String
    let load: Double
    let reps: Double
    let note: String
    let hrAvg: Double
    let hrMax: Double
    let hrMin: Double
    let hrSlope: Double
    let heartRateLogs: [HeartRateLogData]

    init(from record: SetRecord) {
        self.id = record.id?.uuidString ?? ""
        self.cycleIndex = Int(record.cycleIndex)
        self.phase = record.phase ?? ""
        self.startAt = record.startAt
        self.endAt = record.endAt
        self.category = record.category ?? ""
        self.exercise = record.name ?? ""
        self.load = record.load
        self.reps = record.reps
        self.note = record.note ?? ""
        self.hrAvg = record.hrAvg
        self.hrMax = record.hrMax
        self.hrMin = record.hrMin
        self.hrSlope = record.hrSlopeAvg
        self.heartRateLogs = record.heartRateLogs
    }
}