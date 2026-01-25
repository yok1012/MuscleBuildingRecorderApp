#if os(watchOS)
import SwiftUI
import WatchKit

/// Watch用の種目・回数・重量入力ビュー
struct ExerciseInputView: View {
    @Environment(\.dismiss) private var dismiss

    // 入力値
    @State private var selectedCategory: String
    @State private var selectedExercise: String
    @State private var reps: Int
    @State private var weight: Double

    // コールバック
    var onSave: (String, String, Int, Double) -> Void

    // 種目カテゴリと種目のリスト
    private let categories = ["胸", "背中", "肩", "腕", "脚", "腹筋", "その他"]

    private let exercisesByCategory: [String: [String]] = [
        "胸": ["ベンチプレス", "ダンベルプレス", "インクラインプレス", "ディップス", "チェストフライ", "プッシュアップ"],
        "背中": ["デッドリフト", "懸垂", "ラットプルダウン", "ベントオーバーロウ", "シーテッドロウ", "ワンハンドロウ"],
        "肩": ["ショルダープレス", "サイドレイズ", "フロントレイズ", "リアレイズ", "アップライトロウ", "シュラッグ"],
        "腕": ["バーベルカール", "ダンベルカール", "ハンマーカール", "トライセップエクステンション", "スカルクラッシャー", "キックバック"],
        "脚": ["スクワット", "レッグプレス", "レッグカール", "レッグエクステンション", "カーフレイズ", "ランジ"],
        "腹筋": ["クランチ", "レッグレイズ", "プランク", "サイドベント", "アブローラー", "シットアップ"],
        "その他": ["その他"]
    ]

    init(
        currentCategory: String = "胸",
        currentExercise: String = "ベンチプレス",
        currentReps: Int = 10,
        currentWeight: Double = 20.0,
        onSave: @escaping (String, String, Int, Double) -> Void
    ) {
        _selectedCategory = State(initialValue: currentCategory)
        _selectedExercise = State(initialValue: currentExercise)
        _reps = State(initialValue: currentReps)
        _weight = State(initialValue: currentWeight)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // カテゴリ選択
                    categorySection

                    // 種目選択
                    exerciseSection

                    // 回数入力
                    repsSection

                    // 重量入力
                    weightSection

                    // 保存ボタン
                    saveButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .navigationTitle("種目設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Category Section
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("カテゴリ")
                .font(.caption2)
                .foregroundColor(.secondary)

            Picker("カテゴリ", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 50)
            .onChange(of: selectedCategory) { oldValue, newValue in
                // カテゴリ変更時に最初の種目を選択
                if let exercises = exercisesByCategory[newValue], let first = exercises.first {
                    selectedExercise = first
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Exercise Section
    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("種目")
                .font(.caption2)
                .foregroundColor(.secondary)

            let exercises = exercisesByCategory[selectedCategory] ?? ["その他"]
            Picker("種目", selection: $selectedExercise) {
                ForEach(exercises, id: \.self) { exercise in
                    Text(exercise).tag(exercise)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 50)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Reps Section
    private var repsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("回数")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(action: { if reps > 1 { reps -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text("\(reps)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(minWidth: 40)

                Text("回")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { if reps < 100 { reps += 1 } }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)

            // クイック選択
            HStack(spacing: 6) {
                ForEach([5, 8, 10, 12, 15], id: \.self) { value in
                    Button(action: { reps = value }) {
                        Text("\(value)")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(reps == value ? Color.blue : Color.secondary.opacity(0.2))
                            .foregroundColor(reps == value ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Weight Section
    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("重量")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(action: { if weight > 0.5 { weight -= 0.5 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Text(String(format: "%.1f", weight))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(minWidth: 50)

                Text("kg")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { weight += 0.5 }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 4)

            // クイック選択（2.5kg刻み）
            HStack(spacing: 4) {
                ForEach([10.0, 20.0, 30.0, 40.0, 50.0], id: \.self) { value in
                    Button(action: { weight = value }) {
                        Text(String(format: "%.0f", value))
                            .font(.system(size: 10))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(weight == value ? Color.orange : Color.secondary.opacity(0.2))
                            .foregroundColor(weight == value ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // +5kg / -5kg ボタン
            HStack(spacing: 8) {
                Button(action: { if weight >= 5 { weight -= 5 } }) {
                    Text("-5kg")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { weight += 5 }) {
                    Text("+5kg")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.3))
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Save Button
    private var saveButton: some View {
        Button(action: {
            // ハプティックフィードバック
            WKInterfaceDevice.current().play(.success)

            // 保存コールバック
            onSave(selectedCategory, selectedExercise, reps, weight)

            // 画面を閉じる
            dismiss()
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("保存")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Quick Exercise Selection View
/// クイック種目選択ビュー（よく使う種目を素早く選択）
struct QuickExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    var currentCategory: String
    var currentExercise: String
    var onSelect: (String, String) -> Void

    // よく使う種目のショートカット
    private let quickExercises: [(category: String, name: String, icon: String)] = [
        ("胸", "ベンチプレス", "figure.strengthtraining.traditional"),
        ("背中", "デッドリフト", "figure.strengthtraining.functional"),
        ("脚", "スクワット", "figure.stand"),
        ("肩", "ショルダープレス", "figure.arms.open"),
        ("腕", "バーベルカール", "figure.mixed.cardio"),
        ("腹筋", "クランチ", "figure.core.training")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("クイック選択")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(quickExercises, id: \.name) { exercise in
                    Button(action: {
                        WKInterfaceDevice.current().play(.click)
                        onSelect(exercise.category, exercise.name)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: exercise.icon)
                                .font(.caption)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(exercise.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(exercise.category)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if currentExercise == exercise.name {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            currentExercise == exercise.name
                            ? Color.green.opacity(0.2)
                            : Color.secondary.opacity(0.1)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("種目")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ExerciseInputView { category, exercise, reps, weight in
        print("Saved: \(category) - \(exercise), \(reps)回, \(weight)kg")
    }
}
#endif
