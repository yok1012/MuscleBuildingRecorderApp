import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MainTimerView()
                .tabItem {
                    Label("タイマー", systemImage: "timer")
                }
                .tag(0)

            HistoryView()
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
                .tag(2)

            #if DEBUG
            WatchDebugView()
                .tabItem {
                    Label("Debug", systemImage: "applewatch")
                }
                .tag(3)
            #endif
        }
        .onAppear {
            setupHeartRateConnection()
        }
        // セッション復元確認ダイアログ
        .alert("前回のセッションを続けますか？", isPresented: $sessionManager.hasPendingSessionRestore) {
            Button("続ける", role: nil) {
                sessionManager.restoreSession()
            }
            Button("破棄する", role: .destructive) {
                sessionManager.skipSessionRestore()
            }
        } message: {
            if let state = sessionManager.pendingRestoreState {
                Text(sessionRestoreMessage(from: state))
            }
        }
    }

    private func setupHeartRateConnection() {
        Task {
            await heartRateManager.connectToSource(.healthKit)
        }
    }

    /// 復元確認メッセージを生成
    private func sessionRestoreMessage(from state: SessionPersistenceState) -> String {
        let phaseName: String
        switch state.phase {
        case "work": phaseName = "ワーク"
        case "rest": phaseName = "休憩"
        default: phaseName = state.phase
        }

        let workMin = Int(state.totalWorkTime) / 60
        let workSec = Int(state.totalWorkTime) % 60
        let restMin = Int(state.totalRestTime) / 60
        let restSec = Int(state.totalRestTime) % 60

        return """
        \(state.timeSinceSavedString)に中断されました

        フェーズ: \(phaseName)
        ワーク時間: \(workMin)分\(workSec)秒
        休憩時間: \(restMin)分\(restSec)秒
        種目: \(state.selectedExercise)
        """
    }
}