import SwiftUI
import Combine

// テスト用シンプル版
struct ContentViewSimple: View {
    var body: some View {
        TabView {
            MainTimerViewSimple()
                .tabItem {
                    Label("タイマー", systemImage: "timer")
                }
                .tag(0)

            Text("履歴")
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            Text("設定")
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
                .tag(2)
        }
    }
}

struct MainTimerViewSimple: View {
    @State private var phase = "待機中"
    @State private var elapsedTime = "00:00"
    @State private var isRunning = false
    @State private var startTime: Date?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 30) {
            // ヘッダー
            Text("筋トレタイマー")
                .font(.largeTitle)
                .fontWeight(.bold)

            // 現在の状態
            Text(phase)
                .font(.title)
                .padding()
                .background(phaseColor.opacity(0.2))
                .cornerRadius(10)

            // タイマー表示
            Text(elapsedTime)
                .font(.system(size: 60, weight: .thin, design: .monospaced))

            // コントロールボタン
            VStack(spacing: 20) {
                // メインボタン
                Button(action: togglePhase) {
                    Text(buttonTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 60)
                        .background(buttonColor)
                        .cornerRadius(30)
                }

                // 停止ボタン
                if isRunning {
                    Button(action: stop) {
                        Text("停止")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 100, height: 40)
                            .background(Color.gray)
                            .cornerRadius(20)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateTime()
        }
    }

    private var phaseColor: Color {
        switch phase {
        case "筋トレ中": return .red
        case "休憩中": return .blue
        default: return .gray
        }
    }

    private var buttonTitle: String {
        switch phase {
        case "待機中": return "開始"
        case "筋トレ中": return "休憩へ"
        case "休憩中": return "筋トレへ"
        default: return "開始"
        }
    }

    private var buttonColor: Color {
        switch phase {
        case "待機中": return .green
        case "筋トレ中": return .blue
        case "休憩中": return .red
        default: return .green
        }
    }

    private func togglePhase() {
        if !isRunning {
            // 開始
            phase = "筋トレ中"
            isRunning = true
            startTime = Date()
        } else {
            // フェーズ切り替え
            if phase == "筋トレ中" {
                phase = "休憩中"
            } else {
                phase = "筋トレ中"
            }
            startTime = Date()
        }
    }

    private func stop() {
        phase = "待機中"
        isRunning = false
        elapsedTime = "00:00"
        startTime = nil
    }

    private func updateTime() {
        guard isRunning, let startTime = startTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        elapsedTime = String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentViewSimple()
}