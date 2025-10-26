import SwiftUI
import CoreData

struct SettingsView: View {
    @EnvironmentObject var heartRateManager: HeartRateManager
    @EnvironmentObject var dataController: DataController
    @State private var selectedHeartRateSource: HeartRateSourceType = .healthKit
    @State private var showingAirPodsAlert = false
    @State private var showingMasterDataEditor = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("心拍数デバイス")) {
                    ForEach(HeartRateSourceType.allCases, id: \.self) { source in
                        HStack {
                            Image(systemName: source.icon)
                                .foregroundColor(.blue)
                                .frame(width: 30)

                            VStack(alignment: .leading) {
                                Text(source.rawValue)
                                    .font(.headline)
                                Text(source.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if heartRateManager.selectedSourceType == source {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectHeartRateSource(source)
                        }
                    }

                    if heartRateManager.isConnected {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                            Text("現在の心拍数: \(Int(heartRateManager.currentHeartRate)) bpm")
                                .font(.footnote)
                        }
                    }
                }

                Section(header: Text("エクササイズマスタデータ")) {
                    Button(action: { showingMasterDataEditor = true }) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("種目編集")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: resetToDefaults) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                            Text("初期データに戻す")
                                .foregroundColor(.orange)
                        }
                    }
                }

                Section(header: Text("プライバシー")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("データはローカル保存", systemImage: "lock.shield.fill")
                            .foregroundColor(.green)

                        Text("あなたのワークアウトデータは、このデバイスにのみ保存されます。クラウド同期はオフになっています。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if heartRateManager.selectedSourceType == .healthKit {
                            Label("HealthKit連携中", systemImage: "heart.text.square.fill")
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("ビルド")
                        Spacer()
                        Text("2024.1")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showingMasterDataEditor) {
                ExerciseMasterEditorView()
            }
            .alert("AirPods非対応", isPresented: $showingAirPodsAlert) {
                Button("OK") { }
            } message: {
                Text("AirPods（第3世代）は心拍数測定に対応していません。Apple WatchまたはBluetooth心拍計をご利用ください。")
            }
        }
    }

    private func selectHeartRateSource(_ source: HeartRateSourceType) {
        if source == .airpods {
            showingAirPodsAlert = true
            return
        }

        Task {
            await heartRateManager.connectToSource(source)
        }
    }

    private func resetToDefaults() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ExerciseMaster")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)

        do {
            try dataController.container.viewContext.execute(deleteRequest)
            dataController.loadInitialData()
        } catch {
            print("Failed to reset data: \(error)")
        }
    }
}

struct ExerciseMasterEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ExerciseMaster.category, ascending: true),
            NSSortDescriptor(keyPath: \ExerciseMaster.name, ascending: true)
        ]
    ) var exercises: FetchedResults<ExerciseMaster>

    @State private var selectedExercise: ExerciseMaster?
    @State private var showingAddNew = false

    var body: some View {
        NavigationView {
            List {
                ForEach(groupedExercises, id: \.category) { group in
                    Section(header: Text(group.category)) {
                        ForEach(group.exercises, id: \.self) { exercise in
                            ExerciseRow(exercise: exercise)
                                .onTapGesture {
                                    selectedExercise = exercise
                                }
                        }
                        .onDelete { indexSet in
                            deleteExercises(in: group.exercises, at: indexSet)
                        }
                    }
                }
            }
            .navigationTitle("種目マスタ")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddNew = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedExercise) { exercise in
                ExerciseEditView(exercise: exercise)
            }
            .sheet(isPresented: $showingAddNew) {
                AddExerciseView()
            }
        }
    }

    private var groupedExercises: [(category: String, exercises: [ExerciseMaster])] {
        Dictionary(grouping: Array(exercises), by: { $0.category ?? "" })
            .map { (category: $0.key, exercises: $0.value) }
            .sorted { $0.category < $1.category }
    }

    private func deleteExercises(in exercises: [ExerciseMaster], at offsets: IndexSet) {
        for index in offsets {
            dataController.container.viewContext.delete(exercises[index])
        }
        dataController.save()
    }
}

struct ExerciseRow: View {
    let exercise: ExerciseMaster

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name ?? "")
                .font(.headline)
            HStack {
                Text("デフォルト: \(exercise.defaultLoad, specifier: "%.1f") \(exercise.loadUnit ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("×")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(exercise.defaultReps, specifier: "%.0f") \(exercise.repsUnit ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ExerciseEditView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController
    let exercise: ExerciseMaster

    @State private var name: String = ""
    @State private var category: String = ""
    @State private var loadUnit: String = ""
    @State private var repsUnit: String = ""
    @State private var defaultLoad: Double = 0
    @State private var defaultReps: Double = 0

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("種目名", text: $name)
                    TextField("カテゴリー", text: $category)
                }

                Section(header: Text("単位設定")) {
                    TextField("負荷単位", text: $loadUnit)
                    TextField("回数単位", text: $repsUnit)
                }

                Section(header: Text("デフォルト値")) {
                    HStack {
                        Text("負荷:")
                        TextField("", value: $defaultLoad, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text(loadUnit)
                    }
                    HStack {
                        Text("回数:")
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text(repsUnit)
                    }
                }
            }
            .navigationTitle("種目編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            name = exercise.name ?? ""
            category = exercise.category ?? ""
            loadUnit = exercise.loadUnit ?? ""
            repsUnit = exercise.repsUnit ?? ""
            defaultLoad = exercise.defaultLoad
            defaultReps = exercise.defaultReps
        }
    }

    private func saveChanges() {
        exercise.name = name
        exercise.category = category
        exercise.loadUnit = loadUnit
        exercise.repsUnit = repsUnit
        exercise.defaultLoad = defaultLoad
        exercise.defaultReps = defaultReps
        dataController.save()
    }
}

struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataController: DataController

    @State private var name: String = ""
    @State private var category: String = ""
    @State private var loadUnit: String = "kg"
    @State private var repsUnit: String = "回"
    @State private var defaultLoad: Double = 10
    @State private var defaultReps: Double = 10

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("種目名", text: $name)
                    TextField("カテゴリー", text: $category)
                }

                Section(header: Text("単位設定")) {
                    TextField("負荷単位", text: $loadUnit)
                    TextField("回数単位", text: $repsUnit)
                }

                Section(header: Text("デフォルト値")) {
                    HStack {
                        Text("負荷:")
                        TextField("", value: $defaultLoad, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text(loadUnit)
                    }
                    HStack {
                        Text("回数:")
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text(repsUnit)
                    }
                }
            }
            .navigationTitle("新規種目追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("追加") {
                        addExercise()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.isEmpty || category.isEmpty)
                }
            }
        }
    }

    private func addExercise() {
        let context = dataController.container.viewContext
        let exercise = ExerciseMaster(context: context)
        exercise.id = UUID()
        exercise.name = name
        exercise.category = category
        exercise.loadUnit = loadUnit
        exercise.repsUnit = repsUnit
        exercise.defaultLoad = defaultLoad
        exercise.defaultReps = defaultReps
        exercise.isActive = true
        dataController.save()
    }
}