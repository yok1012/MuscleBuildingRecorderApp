import SwiftUI

struct WatchDebugView: View {
    @ObservedObject var watchConnectivity = WatchConnectivityService.shared
    @ObservedObject var heartRateManager = HeartRateManager.shared
    @State private var showingCommands = false

    var body: some View {
        VStack(spacing: 16) {
            // 接続状態
            HStack {
                Circle()
                    .fill(watchConnectivity.isWatchConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text("Watch接続状態")
                    .font(.headline)
                Spacer()
                Text(watchConnectivity.watchStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // 心拍数表示（iPhone HealthKitから直接取得）
            VStack(spacing: 8) {
                Text("心拍数 (HealthKit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(Int(heartRateManager.currentHeartRate))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let lastTime = watchConnectivity.lastMessageTime {
                    Text("最終更新: \(Int(Date().timeIntervalSince(lastTime)))秒前")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                HStack {
                    Label("状態", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(stateText)
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                HStack {
                    Label("タイマー", systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(watchConnectivity.watchElapsedTimeString)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            // コマンドボタン
            VStack(spacing: 12) {
                Text("Watchコマンド")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button(action: {
                        watchConnectivity.startWatchWorkout()
                    }) {
                        Label("開始", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: {
                        watchConnectivity.stopWatchWorkout()
                    }) {
                        Label("停止", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        watchConnectivity.pauseWatchWorkout()
                    }) {
                        Label("一時停止", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        watchConnectivity.resumeWatchWorkout()
                    }) {
                        Label("再開", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)

            // 現在の心拍数ソース
            HStack {
                Text("現在のソース:")
                    .font(.caption)
                Spacer()
                Text(heartRateManager.selectedSourceType.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)

            // デバッグ情報
            VStack(alignment: .leading, spacing: 4) {
                Text("デバッグ情報")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Watch HR: \(Int(watchConnectivity.watchHeartRate)) BPM")
                    .font(.caption2)
                Text("iPhone HR: \(Int(heartRateManager.currentHeartRate)) BPM")
                    .font(.caption2)
                Text("状態: \(heartRateManager.statusMessage)")
                    .font(.caption2)
                if let lastUpdate = heartRateManager.lastUpdateTime {
                    Text("最終更新: \(Int(Date().timeIntervalSince(lastUpdate)))秒前")
                        .font(.caption2)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
    }
}

#Preview {
    WatchDebugView()
}

private extension WatchDebugView {
    var stateText: String {
        switch watchConnectivity.watchWorkoutState {
        case .idle: return "待機中"
        case .running: return "稼働中"
        case .paused: return "一時停止"
        case .ended: return "終了"
        }
    }
}
