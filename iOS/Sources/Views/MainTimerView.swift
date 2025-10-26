import SwiftUI

struct MainTimerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var heartRateManager: HeartRateManager
    @State private var showingInputSheet = false
    @State private var showingSummary = false

    var body: some View {
        VStack(spacing: 20) {
            headerView

            Spacer()

            phaseIndicator

            timerDisplay

            heartRateDisplay

            Spacer()

            controlButtons

            Spacer()
        }
        .padding()
        .background(backgroundGradient)
        .sheet(isPresented: $showingInputSheet) {
            ExerciseInputSheet()
        }
        .fullScreenCover(isPresented: $showingSummary) {
            SessionSummaryView()
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: { showingInputSheet = true }) {
                Label("入力", systemImage: "square.and.pencil")
                    .padding(10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
            }

            Spacer()

            Text("Cycle \(sessionManager.cycleIndex + 1)")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Menu {
                Button(action: {}) {
                    Label("設定", systemImage: "gear")
                }
                Button(action: {}) {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }

    private var phaseIndicator: some View {
        VStack {
            Text(sessionManager.currentPhase.displayName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if sessionManager.currentPhase != .idle {
                HStack {
                    Image(systemName: "dumbbell.fill")
                    Text("\(sessionManager.selectedCategory) - \(sessionManager.selectedExercise)")
                    Image(systemName: "dumbbell.fill")
                }
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var timerDisplay: some View {
        Text(sessionManager.elapsedTimeString)
            .font(.system(size: 72, weight: .thin, design: .monospaced))
            .foregroundColor(.white)
            .shadow(radius: 10)
    }

    private var heartRateDisplay: some View {
        HStack(spacing: 30) {
            VStack {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                Text("\(Int(heartRateManager.currentHeartRate))")
                    .font(.system(size: 36, weight: .medium))
                Text("bpm")
                    .font(.caption)
                    .opacity(0.8)
            }

            VStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(String(format: "%.1f", heartRateManager.heartRateSlope))
                    .font(.system(size: 36, weight: .medium))
                Text("bpm/分")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .foregroundColor(.white)
    }

    private var controlButtons: some View {
        VStack(spacing: 20) {
            mainActionButton

            HStack(spacing: 20) {
                completeButton
                restCompleteButton
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
        }) {
            Text(mainButtonTitle)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 250, height: 80)
                .background(mainButtonColor)
                .cornerRadius(40)
                .shadow(radius: 10)
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: sessionManager.currentPhase)
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
            showingSummary = true
        }) {
            Text("完了")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 100, height: 50)
                .background(Color.gray)
                .cornerRadius(25)
        }
        .disabled(sessionManager.currentPhase == .idle)
        .opacity(sessionManager.currentPhase == .idle ? 0.5 : 1)
    }

    private var restCompleteButton: some View {
        Button(action: {
            sessionManager.saveCurrentCycle()
        }) {
            Text("休憩完了")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 100, height: 50)
                .background(Color.orange)
                .cornerRadius(25)
        }
        .disabled(sessionManager.currentPhase != .rest)
        .opacity(sessionManager.currentPhase != .rest ? 0.5 : 1)
    }

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch sessionManager.currentPhase {
            case .idle: return [.gray, .black]
            case .work: return [.red, .orange]
            case .rest: return [.blue, .cyan]
            }
        }()

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}