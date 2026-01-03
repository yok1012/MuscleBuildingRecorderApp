import SwiftUI
import Combine

/// 心拍数モニタービュー（デバッグ・テスト用）
struct AirPodsConnectionView: View {
    @StateObject private var heartRateManager = HeartRateManager.shared
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 接続状態ヘッダー
                connectionStatusHeader

                // 心拍数表示
                if heartRateManager.isConnected {
                    heartRateDisplay
                }

                // デバイス選択
                deviceSelectionSection

                // 接続ボタン
                connectionButtons

                // エラー表示
                if let error = errorMessage {
                    errorView(message: error)
                }

                Spacer()

                // デバッグ情報（開発用）
                #if DEBUG
                debugInfoSection
                #endif
            }
            .padding()
            .navigationTitle("心拍数モニター")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            heartRateManager.requestAuthorization()
        }
    }

    // MARK: - Connection Status Header
    private var connectionStatusHeader: some View {
        HStack {
            Image(systemName: heartRateManager.isConnected ? "heart.fill" : "heart")
                .foregroundColor(heartRateManager.isConnected ? .red : .gray)
                .font(.system(size: 30))

            VStack(alignment: .leading, spacing: 4) {
                Text(heartRateManager.statusMessage)
                    .font(.headline)

                if let lastUpdate = heartRateManager.lastUpdateTime {
                    Text("最終更新: \(timeAgoString(from: lastUpdate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 接続インジケーター
            if isConnecting {
                ProgressView()
                    .scaleEffect(0.8)
            } else if heartRateManager.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Heart Rate Display
    private var heartRateDisplay: some View {
        VStack(spacing: 10) {
            Text("\(Int(heartRateManager.currentHeartRate))")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.red)

            Text("BPM")
                .font(.title3)
                .foregroundColor(.secondary)

            // 心拍数トレンド
            HStack(spacing: 20) {
                VStack {
                    Text("平均")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(heartRateManager.getHeartRateStats().avg))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack {
                    Text("最大")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(heartRateManager.getHeartRateStats().max))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                VStack {
                    Text("最小")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(heartRateManager.getHeartRateStats().min))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .padding(.top, 10)

            // トレンド表示
            if abs(heartRateManager.heartRateSlope) > 0.5 {
                HStack {
                    Image(systemName: heartRateManager.heartRateSlope > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundColor(heartRateManager.heartRateSlope > 0 ? .orange : .blue)

                    Text(heartRateManager.heartRateSlope > 0 ? "上昇中" : "下降中")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(String(format: "%.1f", abs(heartRateManager.heartRateSlope))) bpm/分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Device Selection
    private var deviceSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("デバイス選択")
                .font(.headline)

            ForEach(HeartRateSourceType.allCases, id: \.self) { source in
                deviceButton(for: source)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func deviceButton(for source: HeartRateSourceType) -> some View {
        Button(action: {
            selectDevice(source)
        }) {
            HStack {
                Image(systemName: source.icon)
                    .font(.title3)
                    .frame(width: 30)

                Text(source.rawValue)
                    .font(.body)

                Spacer()

                if heartRateManager.selectedSourceType == source && heartRateManager.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 15)
            .background(
                heartRateManager.selectedSourceType == source ?
                Color.blue.opacity(0.1) : Color.clear
            )
            .cornerRadius(10)
        }
    }

    // MARK: - Connection Buttons
    private var connectionButtons: some View {
        HStack(spacing: 15) {
            if !heartRateManager.isConnected {
                Button(action: connectToSelectedDevice) {
                    Label("接続", systemImage: "link.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)
            } else {
                Button(action: disconnect) {
                    Label("切断", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Error View
    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button("閉じる") {
                errorMessage = nil
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemYellow).opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Debug Info
    #if DEBUG
    private var debugInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("デバッグ情報")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("接続状態: \(heartRateManager.isConnected ? "接続中" : "未接続")")
                .font(.system(.caption, design: .monospaced))

            Text("選択ソース: \(heartRateManager.selectedSourceType.rawValue)")
                .font(.system(.caption, design: .monospaced))

            Text("現在の心拍数: \(heartRateManager.currentHeartRate) bpm")
                .font(.system(.caption, design: .monospaced))

            if let lastUpdate = heartRateManager.lastUpdateTime {
                Text("最終更新: \(lastUpdate.formatted())")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
    #endif

    // MARK: - Helper Functions
    private func selectDevice(_ source: HeartRateSourceType) {
        heartRateManager.selectedSourceType = source
        errorMessage = nil
    }

    private func connectToSelectedDevice() {
        isConnecting = true
        errorMessage = nil

        Task {
            await heartRateManager.connectToSource(heartRateManager.selectedSourceType)

            await MainActor.run {
                isConnecting = false
                if !heartRateManager.isConnected {
                    errorMessage = "接続に失敗しました"
                }
            }
        }
    }

    private func disconnect() {
        Task {
            await heartRateManager.disconnectCurrentSource()
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "\(Int(interval))秒前"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分前"
        } else {
            return "\(Int(interval / 3600))時間前"
        }
    }
}

// MARK: - Preview
struct AirPodsConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        AirPodsConnectionView()
    }
}
