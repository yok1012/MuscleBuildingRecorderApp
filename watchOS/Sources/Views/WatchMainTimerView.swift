import SwiftUI
import WatchKit

struct WatchMainTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                phaseHeader

                timerDisplay

                heartRateDisplay

                controlButtons
            }
            .padding(.horizontal)
        }
        .background(backgroundGradient)
    }

    private var phaseHeader: some View {
        VStack(spacing: 4) {
            Text(sessionManager.currentPhase.displayName)
                .font(.headline)
                .fontWeight(.bold)

            if sessionManager.currentPhase != .idle {
                Text("\(sessionManager.selectedCategory)")
                    .font(.caption)
                    .opacity(0.8)
                Text("\(sessionManager.selectedExercise)")
                    .font(.caption2)
                    .opacity(0.8)
            }
        }
        .foregroundColor(.white)
    }

    private var timerDisplay: some View {
        Text(sessionManager.elapsedTimeString)
            .font(.system(size: 40, weight: .thin, design: .monospaced))
            .foregroundColor(.white)
    }

    private var heartRateDisplay: some View {
        HStack(spacing: 15) {
            VStack {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("\(Int(heartRateManager.currentHeartRate))")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("bpm")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }

            VStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(String(format: "%.1f", heartRateManager.heartRateSlope))
                    .font(.title3)
                    .fontWeight(.medium)
                Text("bpm/分")
                    .font(.system(size: 9))
                    .opacity(0.7)
            }
        }
        .foregroundColor(.white)
    }

    private var controlButtons: some View {
        VStack(spacing: 8) {
            mainActionButton

            if sessionManager.currentPhase != .idle {
                HStack(spacing: 8) {
                    completeButton
                    restCompleteButton
                }
            }
        }
    }

    private var mainActionButton: some View {
        Button(action: {
            withAnimation(.spring()) {
                if sessionManager.currentPhase == .idle {
                    sessionManager.startSession()
                } else {
                    sessionManager.togglePhase()
                }
            }
            WKInterfaceDevice.current().play(.click)
        }) {
            Text(mainButtonTitle)
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(mainButtonColor)
                .cornerRadius(20)
        }
    }

    private var mainButtonTitle: String {
        switch sessionManager.currentPhase {
        case .idle: return "スタート"
        case .work: return "休憩へ"
        case .rest: return "筋トレへ"
        }
    }

    private var mainButtonColor: Color {
        switch sessionManager.currentPhase {
        case .idle: return .green
        case .work: return .blue
        case .rest: return .red
        }
    }

    private var completeButton: some View {
        Button(action: {
            sessionManager.endSession()
            WKInterfaceDevice.current().play(.stop)
        }) {
            Text("完了")
                .font(.caption2)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.gray)
                .cornerRadius(15)
        }
    }

    private var restCompleteButton: some View {
        Button(action: {
            sessionManager.saveCurrentCycle()
            WKInterfaceDevice.current().play(.success)
        }) {
            Text("保存")
                .font(.caption2)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange)
                .cornerRadius(15)
        }
        .disabled(sessionManager.currentPhase != .rest)
        .opacity(sessionManager.currentPhase != .rest ? 0.5 : 1)
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch sessionManager.currentPhase {
            case .idle: return [.gray.opacity(0.3), .black]
            case .work: return [.red.opacity(0.3), .black]
            case .rest: return [.blue.opacity(0.3), .black]
            }
        }()

        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}