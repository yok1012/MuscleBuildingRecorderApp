import SwiftUI

struct ExerciseInputSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    @State private var availableCategories: [String] = []
    @State private var availableExercises: [String] = []
    @State private var loadInputText: String = ""
    @State private var repsInputText: String = ""
    @FocusState private var isLoadFieldFocused: Bool
    @FocusState private var isRepsFieldFocused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("エクササイズ選択")) {
                    Picker("カテゴリー", selection: $sessionManager.selectedCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .onChange(of: sessionManager.selectedCategory) { oldValue, newValue in
                        updateAvailableExercises()
                        if let firstExercise = availableExercises.first {
                            sessionManager.selectedExercise = firstExercise
                            sessionManager.loadDefaultExerciseValues()
                        }
                    }

                    Picker("種目", selection: $sessionManager.selectedExercise) {
                        ForEach(availableExercises, id: \.self) { exercise in
                            Text(exercise).tag(exercise)
                        }
                    }
                    .onChange(of: sessionManager.selectedExercise) { oldValue, newValue in
                        sessionManager.loadDefaultExerciseValues()
                    }
                }

                Section(header: Text("負荷設定")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 直接入力フィールド + 単位表示
                        HStack(spacing: 8) {
                            Text("負荷:")
                                .foregroundColor(.secondary)

                            TextField("0.0", text: $loadInputText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .focused($isLoadFieldFocused)
                                .onChange(of: loadInputText) { _, newValue in
                                    if let value = Double(newValue) {
                                        sessionManager.currentLoad = value
                                    }
                                }

                            Text(sessionManager.loadUnit)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(sessionManager.currentLoad, specifier: "%.1f")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }

                        Slider(
                            value: $sessionManager.currentLoad,
                            in: 0...200,
                            step: getLoadStep()
                        )
                        .onChange(of: sessionManager.currentLoad) { _, newValue in
                            if !isLoadFieldFocused {
                                loadInputText = String(format: "%.1f", newValue)
                            }
                        }

                        HStack {
                            Stepper("", value: $sessionManager.currentLoad, step: getLoadStep())
                                .labelsHidden()
                            Spacer()
                            Button("リセット") {
                                sessionManager.loadDefaultExerciseValues()
                                loadInputText = String(format: "%.1f", sessionManager.currentLoad)
                            }
                            .font(.caption)
                        }
                    }
                }

                Section(header: Text("回数/時間設定")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 直接入力フィールド + 単位表示
                        HStack(spacing: 8) {
                            Text("回数:")
                                .foregroundColor(.secondary)

                            TextField("0", text: $repsInputText)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                                .focused($isRepsFieldFocused)
                                .onChange(of: repsInputText) { _, newValue in
                                    if let value = Double(newValue) {
                                        sessionManager.currentReps = value
                                    }
                                }

                            Text(sessionManager.repsUnit)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(sessionManager.currentReps, specifier: "%.0f")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }

                        Slider(
                            value: $sessionManager.currentReps,
                            in: 1...100,
                            step: 1
                        )
                        .onChange(of: sessionManager.currentReps) { _, newValue in
                            if !isRepsFieldFocused {
                                repsInputText = String(format: "%.0f", newValue)
                            }
                        }

                        Stepper("", value: $sessionManager.currentReps, step: 1)
                            .labelsHidden()
                    }
                }

                Section(header: Text("メモ")) {
                    TextEditor(text: $sessionManager.currentNote)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if sessionManager.currentNote.isEmpty {
                                    Text("フォームの注意点やポイントを記入...")
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Label("現在の心拍数", systemImage: "heart.fill")
                                .font(.caption)
                            Text("\(Int(sessionManager.heartRateManager.currentHeartRate)) bpm")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Label("心拍勾配", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                            Text("\(sessionManager.heartRateManager.heartRateSlope, specifier: "%.1f") bpm/分")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("エクササイズ入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            loadCategories()
            updateAvailableExercises()
            // 初期値をテキストフィールドに設定
            loadInputText = String(format: "%.1f", sessionManager.currentLoad)
            repsInputText = String(format: "%.0f", sessionManager.currentReps)
        }
    }

    private func loadCategories() {
        availableCategories = sessionManager.getAvailableCategories()
    }

    private func updateAvailableExercises() {
        availableExercises = sessionManager.getExercises(for: sessionManager.selectedCategory)
    }

    private func getLoadStep() -> Double {
        switch sessionManager.loadUnit {
        case "kg": return 2.5
        case "W": return 10
        case "レベル": return 1
        default: return 1
        }
    }
}

private extension SessionManager {
    var heartRateManager: HeartRateManager {
        HeartRateManager.shared
    }
}