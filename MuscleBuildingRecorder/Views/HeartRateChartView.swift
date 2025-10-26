import SwiftUI

struct HeartRateChartView: View {
    let session: Session
    @State private var selectedLog: HeartRateLogData?
    @State private var showingFullScreen = false

    private var heartRateLogs: [HeartRateLogData] {
        // 現在のセッションまたは過去のセッションからログを取得
        if session.endedAt != nil {
            // 過去のセッション: SetRecordから生成
            return session.generateHeartRateLogs()
        } else {
            // 現在のセッション: ログマネージャーから取得
            return session.allHeartRateLogs
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    private var statistics: (min: Double, max: Double, avg: Double) {
        session.heartRateStatistics ?? (min: 0, max: 0, avg: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Label("心拍数グラフ", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundColor(.red)

                Spacer()

                Button(action: { showingFullScreen = true }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if !heartRateLogs.isEmpty {
                // 統計情報
                HStack(spacing: 16) {
                    StatisticView(
                        title: "最小",
                        value: "\(Int(statistics.min))",
                        unit: "bpm",
                        color: .blue
                    )
                    StatisticView(
                        title: "平均",
                        value: "\(Int(statistics.avg))",
                        unit: "bpm",
                        color: .green
                    )
                    StatisticView(
                        title: "最大",
                        value: "\(Int(statistics.max))",
                        unit: "bpm",
                        color: .red
                    )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

                // カスタムグラフビュー
                SimpleHeartRateGraph(logs: heartRateLogs, selectedLog: $selectedLog)
                    .frame(height: 200)
                    .padding(.horizontal)

                // 選択されたデータポイントの詳細
                if let selected = selectedLog {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("時刻: \(dateFormatter.string(from: selected.timestamp))")
                                .font(.caption)
                            Text("心拍数: \(Int(selected.heartRate)) bpm")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        Text(selected.phase)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selected.phase == "Work" ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("心拍数データがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .sheet(isPresented: $showingFullScreen) {
            FullScreenHeartRateChartView(session: session)
        }
    }
}

// シンプルなカスタムグラフビュー
struct SimpleHeartRateGraph: View {
    let logs: [HeartRateLogData]
    @Binding var selectedLog: HeartRateLogData?

    private var minHeartRate: Double {
        logs.map { $0.heartRate }.min() ?? 40
    }

    private var maxHeartRate: Double {
        logs.map { $0.heartRate }.max() ?? 200
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // グリッド背景
                Path { path in
                    let stepY = geometry.size.height / 5
                    for i in 0...5 {
                        let y = CGFloat(i) * stepY
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                // 心拍数ライン
                if !logs.isEmpty {
                    Path { path in
                        let range = maxHeartRate - minHeartRate
                        let xStep = geometry.size.width / CGFloat(max(logs.count - 1, 1))

                        for (index, log) in logs.enumerated() {
                            let x = CGFloat(index) * xStep
                            let normalizedY = (log.heartRate - minHeartRate) / range
                            let y = geometry.size.height * (1 - normalizedY)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )

                    // データポイント
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                        let x = CGFloat(index) * (geometry.size.width / CGFloat(max(logs.count - 1, 1)))
                        let normalizedY = (log.heartRate - minHeartRate) / (maxHeartRate - minHeartRate)
                        let y = geometry.size.height * (1 - normalizedY)

                        Circle()
                            .fill(log.phase == "Work" ? Color.red : Color.blue)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                            .onTapGesture {
                                selectedLog = log
                            }
                    }
                }
            }
        }
    }
}

// 統計ビュー
private struct StatisticView: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// フルスクリーン表示用のビュー
struct FullScreenHeartRateChartView: View {
    let session: Session
    @Environment(\.dismiss) var dismiss
    @State private var selectedLog: HeartRateLogData?

    private var heartRateLogs: [HeartRateLogData] {
        // 現在のセッションまたは過去のセッションからログを取得
        if session.endedAt != nil {
            // 過去のセッション: SetRecordから生成
            return session.generateHeartRateLogs()
        } else {
            // 現在のセッション: ログマネージャーから取得
            return session.allHeartRateLogs
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 詳細グラフ
                    if !heartRateLogs.isEmpty {
                        SimpleHeartRateGraph(logs: heartRateLogs, selectedLog: $selectedLog)
                            .frame(height: 400)
                            .padding()

                        // 選択されたデータの詳細
                        if let selected = selectedLog {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("時刻: \(dateFormatter.string(from: selected.timestamp))")
                                        .font(.body)
                                    Text("心拍数: \(Int(selected.heartRate)) bpm")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                                Text(selected.phase)
                                    .font(.body)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected.phase == "Work" ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                                    .cornerRadius(6)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }

                        // フェーズごとの分析
                        PhaseAnalysisView(heartRateLogs: heartRateLogs)
                    }
                }
            }
            .navigationTitle("心拍数詳細分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// フェーズごとの分析ビュー
private struct PhaseAnalysisView: View {
    let heartRateLogs: [HeartRateLogData]

    private var workLogs: [HeartRateLogData] {
        heartRateLogs.filter { $0.phase == "Work" }
    }

    private var restLogs: [HeartRateLogData] {
        heartRateLogs.filter { $0.phase == "Rest" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("フェーズ別分析")
                .font(.headline)
                .padding(.horizontal)

            HStack(spacing: 16) {
                PhaseStatCard(
                    title: "ワークフェーズ",
                    logs: workLogs,
                    color: .red
                )
                PhaseStatCard(
                    title: "レストフェーズ",
                    logs: restLogs,
                    color: .blue
                )
            }
            .padding(.horizontal)
        }
    }
}

private struct PhaseStatCard: View {
    let title: String
    let logs: [HeartRateLogData]
    let color: Color

    private var stats: (min: Double, max: Double, avg: Double) {
        guard !logs.isEmpty else { return (0, 0, 0) }
        let heartRates = logs.map { $0.heartRate }
        return (
            min: heartRates.min() ?? 0,
            max: heartRates.max() ?? 0,
            avg: heartRates.reduce(0, +) / Double(heartRates.count)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "heart.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("最小:")
                        .font(.caption2)
                    Text("\(Int(stats.min)) bpm")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("平均:")
                        .font(.caption2)
                    Text("\(Int(stats.avg)) bpm")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("最大:")
                        .font(.caption2)
                    Text("\(Int(stats.max)) bpm")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}