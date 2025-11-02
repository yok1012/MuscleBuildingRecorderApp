import SwiftUI
import Combine

struct SensorGraphView: View {
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @State private var recentSamples: [(timestamp: Date, ax: Double, ay: Double, az: Double, gx: Double?, gy: Double?, gz: Double?)] = []
    @State private var timer: Timer?
    @State private var graphScale: Double = 2.0 // G範囲
    @State private var showGyro = false
    @State private var selectedSensor = "accelerometer"

    private let maxSamples = 100 // 表示するサンプル数

    var body: some View {
        VStack(spacing: 16) {
            // ヘッダー
            HStack {
                Label("リアルタイムセンサーグラフ", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                if sensorLogManager.isLogging {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("記録中")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal)

            // センサー選択
            Picker("センサー", selection: $selectedSensor) {
                Text("加速度").tag("accelerometer")
                if sensorLogManager.enabledSensors.contains("gyro") {
                    Text("ジャイロ").tag("gyroscope")
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            // グラフ本体
            GeometryReader { geometry in
                ZStack {
                    // 背景グリッド
                    GridBackground(scale: graphScale)

                    // グラフ描画
                    if !recentSamples.isEmpty {
                        if selectedSensor == "accelerometer" {
                            // 加速度グラフ
                            // X軸（赤）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.map { $0.ax },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.red, lineWidth: 2)

                            // Y軸（緑）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.map { $0.ay },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.green, lineWidth: 2)

                            // Z軸（青）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.map { $0.az },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.blue, lineWidth: 2)
                        } else if selectedSensor == "gyroscope" {
                            // ジャイログラフ
                            // X軸（赤）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.compactMap { $0.gx },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.red, lineWidth: 2)

                            // Y軸（緑）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.compactMap { $0.gy },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.green, lineWidth: 2)

                            // Z軸（青）
                            Path { path in
                                drawLine(path: &path,
                                       data: recentSamples.compactMap { $0.gz },
                                       width: geometry.size.width,
                                       height: geometry.size.height,
                                       scale: graphScale)
                            }
                            .stroke(Color.blue, lineWidth: 2)
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // 凡例と統計
            HStack(spacing: 20) {
                if selectedSensor == "accelerometer" {
                    LegendItem(color: .red, label: "X軸", value: recentSamples.last?.ax ?? 0, unit: "G")
                    LegendItem(color: .green, label: "Y軸", value: recentSamples.last?.ay ?? 0, unit: "G")
                    LegendItem(color: .blue, label: "Z軸", value: recentSamples.last?.az ?? 0, unit: "G")
                } else if selectedSensor == "gyroscope" {
                    LegendItem(color: .red, label: "X軸", value: recentSamples.last?.gx ?? 0, unit: "rad/s")
                    LegendItem(color: .green, label: "Y軸", value: recentSamples.last?.gy ?? 0, unit: "rad/s")
                    LegendItem(color: .blue, label: "Z軸", value: recentSamples.last?.gz ?? 0, unit: "rad/s")
                }
            }
            .padding(.horizontal)

            // スケール調整
            HStack {
                Text("スケール:")
                    .font(.caption)
                Slider(value: $graphScale, in: 0.5...4.0, step: 0.5)
                    .frame(width: 150)
                Text("±\(graphScale, specifier: "%.1f")G")
                    .font(.caption)
                    .frame(width: 50)
            }
            .padding(.horizontal)

            // サンプル情報
            HStack {
                Text("サンプル数: \(sensorLogManager.sampleCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let lastTime = sensorLogManager.lastSampleTime {
                    Text("最終更新: \(lastTime, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func drawLine(path: inout Path, data: [Double], width: CGFloat, height: CGFloat, scale: Double) {
        guard !data.isEmpty else { return }

        let xStep = width / CGFloat(max(data.count - 1, 1))
        let midY = height / 2

        for (index, value) in data.enumerated() {
            let x = CGFloat(index) * xStep
            let normalizedValue = value / scale // -1 to 1 範囲に正規化
            let y = midY - (normalizedValue * midY * 0.8) // 80%のスケール

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateSamples()
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func updateSamples() {
        // SensorLogManagerから最新データを取得
        recentSamples = sensorLogManager.recentSamples
    }
}

struct GridBackground: View {
    let scale: Double

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // 横線（5本）
                let yStep = geometry.size.height / 4
                for i in 0...4 {
                    let y = CGFloat(i) * yStep
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }

                // 縦線（10本）
                let xStep = geometry.size.width / 10
                for i in 0...10 {
                    let x = CGFloat(i) * xStep
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }

                // 中心線
                let midY = geometry.size.height / 2
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: geometry.size.width, y: midY))
            }
            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(value, specifier: "%.3f")\(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct SensorGraphView_Previews: PreviewProvider {
    static var previews: some View {
        SensorGraphView()
    }
}