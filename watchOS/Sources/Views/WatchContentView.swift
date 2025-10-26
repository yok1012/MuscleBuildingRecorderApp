import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager

    var body: some View {
        TabView {
            WatchMainTimerView()
                .tag(0)

            WatchExerciseInputView()
                .tag(1)

            WatchQuickStatsView()
                .tag(2)
        }
        .tabViewStyle(PageTabViewStyle())
        .onAppear {
            setupHeartRate()
        }
    }

    private func setupHeartRate() {
        Task {
            await heartRateManager.connectToSource(.healthKit)
        }
    }
}