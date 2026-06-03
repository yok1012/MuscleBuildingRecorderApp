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
                            Text(exercise.localizedSeed).tag(exercise)
                        }
                    }
                    .onChange(of: sessionManager.selectedExercise) { oldValue, newValue in
                        sessionManager.loadDefaultExerciseValues()
                    }
                }

                Section(header: Text("負荷設定")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 現在値の大きな表示
                        HStack {
                            Spacer()
                            Text("\(sessionManager.currentLoad, specifier: "%.1f")")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.blue)
                            Text(sessionManager.loadUnit.localizedSeed)
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        // インクリメンタルボタン（減少）
                        HStack(spacing: 6) {
                            incrementButton(value: -5, color: .red, for: "load")
                            incrementButton(value: -1, color: .orange, for: "load")
                        }

                        // インクリメンタルボタン（増加）
                        HStack(spacing: 6) {
                            incrementButton(value: +1, color: .green.opacity(0.7), for: "load")
                            incrementButton(value: +5, color: .green, for: "load")
                        }

                        // 直接入力フィールド
                        HStack(spacing: 8) {
                            Text("直接入力:")
                                .foregroundColor(.secondary)
                                .font(.caption)

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

                            Spacer()

                            Button("リセット") {
                                sessionManager.loadDefaultExerciseValues()
                                loadInputText = String(format: "%.1f", sessionManager.currentLoad)
                            }
                            .font(.caption)
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
                    }
                }

                Section(header: Text("回数/時間設定")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 現在値の大きな表示
                        HStack {
                            Spacer()
                            Text("\(sessionManager.currentReps, specifier: "%.0f")")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(.green)
                            Text(sessionManager.repsUnit.localizedSeed)
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        // インクリメンタルボタン（減少）
                        HStack(spacing: 6) {
                            incrementButton(value: -5, color: .red, for: "reps")
                            incrementButton(value: -1, color: .orange, for: "reps")
                        }

                        // インクリメンタルボタン（増加）
                        HStack(spacing: 6) {
                            incrementButton(value: +1, color: .green.opacity(0.7), for: "reps")
                            incrementButton(value: +5, color: .green, for: "reps")
                        }

                        // 直接入力フィールド
                        HStack(spacing: 8) {
                            Text("直接入力:")
                                .foregroundColor(.secondary)
                                .font(.caption)

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

                            Spacer()
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
        case "kg": return 1
        case "W": return 10
        case "レベル": return 1
        default: return 1
        }
    }

    // MARK: - Increment Button
    @ViewBuilder
    private func incrementButton(value: Double, color: Color, for type: String) -> some View {
        Button(action: {
            // 触覚フィードバック
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            withAnimation(.easeInOut(duration: 0.1)) {
                if type == "load" {
                    let newValue = max(0, sessionManager.currentLoad + value)
                    sessionManager.currentLoad = newValue
                    loadInputText = String(format: "%.1f", newValue)
                } else {
                    let newValue = max(1, sessionManager.currentReps + value)
                    sessionManager.currentReps = newValue
                    repsInputText = String(format: "%.0f", newValue)
                }
            }
        }) {
            Text(value >= 0 ? "+\(formatIncrementValue(value))" : "\(formatIncrementValue(value))")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(color)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)  // Form内でタップが正しく検出されるように
    }

    private func formatIncrementValue(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

private extension SessionManager {
    var heartRateManager: HeartRateManager {
        HeartRateManager.shared
    }
}