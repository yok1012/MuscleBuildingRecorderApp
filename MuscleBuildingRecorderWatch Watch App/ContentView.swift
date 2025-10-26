import SwiftUI
import HealthKit

struct ContentView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @State private var showingWorkoutView = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 心拍数表示
                VStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.red)

                    Text("\(Int(workoutManager.heartRate)) bpm")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                // ワークアウトボタン
                Button(action: {
                    if workoutManager.isWorkoutActive {
                        workoutManager.endWorkout()
                    } else {
                        workoutManager.startWorkout()
                        showingWorkoutView = true
                    }
                }) {
                    Label(
                        workoutManager.isWorkoutActive ? "終了" : "開始",
                        systemImage: workoutManager.isWorkoutActive ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(workoutManager.isWorkoutActive ? .red : .green)

                // ワークアウト時間
                if workoutManager.isWorkoutActive {
                    Text(workoutManager.elapsedTimeString)
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .navigationTitle("筋トレ記録")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingWorkoutView) {
            WorkoutView(workoutManager: workoutManager)
        }
        .onAppear {
            workoutManager.requestAuthorization()
        }
    }
}

struct WorkoutView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // タイマー表示
                Text(workoutManager.elapsedTimeString)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospacedDigit()

                // 心拍数
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("\(Int(workoutManager.heartRate)) bpm")
                        .font(.title3)
                }

                // カロリー
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("\(Int(workoutManager.activeCalories)) kcal")
                        .font(.title3)
                }

                Divider()

                // コントロールボタン
                HStack(spacing: 20) {
                    Button(action: {
                        workoutManager.togglePause()
                    }) {
                        Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.yellow)

                    Button(action: {
                        workoutManager.endWorkout()
                        dismiss()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .padding()
        }
        .navigationTitle("ワークアウト中")
        .navigationBarTitleDisplayMode(.inline)
    }
}