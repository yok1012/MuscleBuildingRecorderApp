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
        }
        .onAppear {
            setupHeartRateConnection()
        }
    }

    private func setupHeartRateConnection() {
        Task {
            await heartRateManager.connectToSource(.healthKit)
        }
    }
}