import SwiftUI
import UniformTypeIdentifiers

struct SessionSummaryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    @State private var sessionRecords: [SetRecord] = []
    @State private var showingShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    heartRateCard
                    cyclesTable
                    exportButtons
                }
                .padding()
            }
            .navigationTitle("セッションサマリー")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadSessionData()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("セッション統計")
                .font(.headline)

            HStack {
                StatItem(
                    icon: "clock.fill",
                    title: "総時間",
                    value: formatTime(totalSeconds),
                    color: .blue
                )

                Spacer()

                StatItem(
                    icon: "dumbbell.fill",
                    title: "ワーク時間",
                    value: formatTime(workSeconds),
                    color: .red
                )

                Spacer()

                StatItem(
                    icon: "pause.circle.fill",
                    title: "休憩時間",
                    value: formatTime(restSeconds),
                    color: .green
                )
            }

            HStack {
                StatItem(
                    icon: "sum",
                    title: "総ボリューム",
                    value: "\(Int(totalVolume))",
                    color: .orange
                )

                Spacer()

                StatItem(
                    icon: "arrow.triangle.2.circlepath",
                    title: "サイクル数",
                    value: "\(cycleCount)",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("心拍数統計")
                .font(.headline)

            HStack {
                HeartRateItem(
                    title: "平均",
                    value: averageHeartRate,
                    icon: "heart.fill"
                )

                Spacer()

                HeartRateItem(
                    title: "最大",
                    value: maxHeartRate,
                    icon: "heart.circle.fill"
                )

                Spacer()

                HeartRateItem(
                    title: "最小",
                    value: minHeartRate,
                    icon: "heart"
                )
            }

            if let zones = heartRateZones {
                VStack(alignment: .leading, spacing: 5) {
                    Text("心拍ゾーン滞在時間")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(zones, id: \.zone) { zoneData in
                        HStack {
                            Circle()
                                .fill(zoneData.color)
                                .frame(width: 8, height: 8)
                            Text(zoneData.zone)
                                .font(.caption)
                            Spacer()
                            Text(formatTime(zoneData.seconds))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var cyclesTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("サイクル詳細")
                .font(.headline)

            ForEach(groupedRecords, id: \.cycleIndex) { cycle in
                CycleRow(cycleData: cycle)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var exportButtons: some View {
        HStack(spacing: 20) {
            Button(action: exportCSV) {
                Label("CSVエクスポート", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Button(action: exportJSON) {
                Label("JSONエクスポート", systemImage: "doc.badge.gearshape")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    private var totalSeconds: Int {
        workSeconds + restSeconds
    }

    private var workSeconds: Int {
        Int(sessionManager.currentSession?.totalWorkSec ?? 0)
    }

    private var restSeconds: Int {
        Int(sessionManager.currentSession?.totalRestSec ?? 0)
    }

    private var totalVolume: Double {
        sessionManager.currentSession?.totalVolume ?? 0
    }

    private var cycleCount: Int {
        Set(sessionRecords.map { $0.cycleIndex }).count
    }

    private var averageHeartRate: Double {
        let rates = sessionRecords.compactMap { $0.hrAvg }.filter { $0 > 0 }
        return rates.isEmpty ? 0 : rates.reduce(0, +) / Double(rates.count)
    }

    private var maxHeartRate: Double {
        sessionRecords.compactMap { $0.hrMax }.max() ?? 0
    }

    private var minHeartRate: Double {
        sessionRecords.compactMap { $0.hrMin }.filter { $0 > 0 }.min() ?? 0
    }

    private var heartRateZones: [(zone: String, seconds: Int, color: Color)]? {
        nil
    }

    private var groupedRecords: [CycleData] {
        Dictionary(grouping: sessionRecords, by: { $0.cycleIndex })
            .map { CycleData(cycleIndex: Int($0.key), records: $0.value) }
            .sorted { $0.cycleIndex < $1.cycleIndex }
    }

    private func loadSessionData() {
        guard let session = sessionManager.currentSession,
              let records = session.setRecords?.allObjects as? [SetRecord] else { return }
        sessionRecords = records.sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func exportCSV() {
        let csv = CSVExporter.export(session: sessionManager.currentSession, records: sessionRecords)
        saveAndShare(content: csv, filename: "workout_\(Date().ISO8601Format()).csv", type: .commaSeparatedText)
    }

    private func exportJSON() {
        let json = JSONExporter.export(session: sessionManager.currentSession, records: sessionRecords)
        saveAndShare(content: json, filename: "workout_\(Date().ISO8601Format()).json", type: .json)
    }

    private func saveAndShare(content: String, filename: String, type: UTType) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showingShareSheet = true
        } catch {
            print("Failed to save file: \(error)")
        }
    }
}

struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct HeartRateItem: View {
    let title: String
    let value: Double
    let icon: String

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.red)
            Text("\(Int(value))")
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CycleData {
    let cycleIndex: Int
    let records: [SetRecord]
}

struct CycleRow: View {
    let cycleData: CycleData

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Cycle \(cycleData.cycleIndex + 1)")
                .font(.caption)
                .fontWeight(.bold)

            ForEach(cycleData.records.sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }, id: \.id) { record in
                HStack {
                    Image(systemName: record.phase == "Work" ? "dumbbell.fill" : "pause.circle")
                        .foregroundColor(record.phase == "Work" ? .red : .blue)

                    VStack(alignment: .leading) {
                        Text("\(record.category ?? "") - \(record.name ?? "")")
                            .font(.footnote)
                        HStack {
                            Text("\(record.load, specifier: "%.1f") × \(Int(record.reps))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let note = record.note, !note.isEmpty {
                                Text("📝")
                                    .font(.caption)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(Int(record.hrAvg)) bpm")
                            .font(.caption)
                        if let duration = calculateDuration(record) {
                            Text(duration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 5)
    }

    private func calculateDuration(_ record: SetRecord) -> String? {
        guard let start = record.startAt, let end = record.endAt else { return nil }
        let seconds = Int(end.timeIntervalSince(start))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}