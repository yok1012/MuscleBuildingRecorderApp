import SwiftUI

struct WatchQuickStatsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("統計")
                    .font(.headline)
                    .foregroundColor(.white)

                if sessionManager.currentPhase == .idle {
                    IdleStateView()
                } else {
                    ActiveStatsView()
                }
            }
            .padding(.horizontal)
        }
        .background(Color.black)
    }
}

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)

            Text("セッション未開始")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("ワークアウトを開始すると\n統計が表示されます")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }
}

struct ActiveStatsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager

    private var totalTime: String {
        guard let startTime = sessionManager.currentSession?.startedAt else {
            return "00:00"
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var currentVolume: Double {
        sessionManager.currentLoad * sessionManager.currentReps
    }

    var body: some View {
        VStack(spacing: 8) {
            StatRow(
                icon: "clock.fill",
                title: "総時間",
                value: totalTime,
                color: .blue
            )

            StatRow(
                icon: "arrow.triangle.2.circlepath",
                title: "サイクル",
                value: "\(sessionManager.cycleIndex + 1)",
                color: .purple
            )

            StatRow(
                icon: "sum",
                title: "現在ボリューム",
                value: "\(Int(currentVolume))",
                color: .orange
            )

            Divider()
                .background(Color.gray)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("HR", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("\(Int(heartRateManager.currentHeartRate))")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("bpm")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Label("勾配", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(heartRateManager.heartRateSlope, specifier: "%.1f")")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("bpm/分")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
    }
}

struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
    }
}