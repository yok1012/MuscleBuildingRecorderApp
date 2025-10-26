import SwiftUI
import WatchKit

struct WatchExerciseInputView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("エクササイズ")
                    .font(.headline)
                    .foregroundColor(.white)

                exerciseInfo

                loadControl

                repsControl

                noteSection
            }
            .padding(.horizontal)
        }
        .background(Color.black)
    }

    private var exerciseInfo: some View {
        VStack(spacing: 4) {
            Text(sessionManager.selectedCategory)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(sessionManager.selectedExercise)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }

    private var loadControl: some View {
        VStack(spacing: 4) {
            Text("負荷")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(action: {
                    sessionManager.currentLoad = max(0, sessionManager.currentLoad - getLoadStep())
                    WKInterfaceDevice.current().play(.click)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }

                VStack(spacing: 2) {
                    Text("\(sessionManager.currentLoad, specifier: "%.1f")")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(sessionManager.loadUnit)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50)

                Button(action: {
                    sessionManager.currentLoad += getLoadStep()
                    WKInterfaceDevice.current().play(.click)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }

    private var repsControl: some View {
        VStack(spacing: 4) {
            Text("回数")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(action: {
                    sessionManager.currentReps = max(1, sessionManager.currentReps - 1)
                    WKInterfaceDevice.current().play(.click)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }

                VStack(spacing: 2) {
                    Text("\(Int(sessionManager.currentReps))")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(sessionManager.repsUnit)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 50)

                Button(action: {
                    sessionManager.currentReps += 1
                    WKInterfaceDevice.current().play(.click)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }

    private var noteSection: some View {
        VStack(spacing: 4) {
            Text("メモ")
                .font(.caption2)
                .foregroundColor(.secondary)

            if sessionManager.currentNote.isEmpty {
                Button(action: openDictation) {
                    HStack {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                        Text("音声入力")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            } else {
                VStack(spacing: 4) {
                    Text(sessionManager.currentNote)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Button(action: {
                        sessionManager.currentNote = ""
                    }) {
                        Text("クリア")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
    }

    private func getLoadStep() -> Double {
        switch sessionManager.loadUnit {
        case "kg": return 2.5
        case "W": return 10
        case "レベル": return 1
        default: return 1
        }
    }

    private func openDictation() {
        // In actual implementation, this would open dictation
        // For now, just provide haptic feedback
        WKInterfaceDevice.current().play(.click)
    }
}