import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var heartRateManager: HeartRateManager
    @Environment(\.managedObjectContext) var viewContext
    @State private var selectedHeartRateSource: HeartRateSourceType = .healthKit
    @State private var showingAirPodsAlert = false
    @State private var showingMasterDataEditor = false
    @State private var showingExportOptions = false
    @State private var exportType: ExportType = .csvDetailed
    @State private var showingExporter = false
    @State private var exportData: ExportData?
    @State private var showingSuccessAlert = false
    @State private var exportMessage = ""

    // センサーログ関連の状態
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @State private var isAccelLogging = false
    @State private var selectedAccelRate = 50
    @State private var showingSensorExportAlert = false
    @State private var sensorExportData: ExportData?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.startedAt, ascending: false)]
    ) private var sessions: FetchedResults<Session>

    private var dataController: DataController {
        DataController.shared
    }

    enum ExportType: String, CaseIterable {
        case csvDetailed = "CSV (詳細)"
        case csvSummary = "CSV (サマリー)"
        case jsonNormal = "JSON (通常)"
        case jsonWithStats = "JSON (統計付き)"

        var fileExtension: String {
            switch self {
            case .csvDetailed, .csvSummary:
                return "csv"
            case .jsonNormal, .jsonWithStats:
                return "json"
            }
        }

        var contentType: UTType {
            switch self {
            case .csvDetailed, .csvSummary:
                return .commaSeparatedText
            case .jsonNormal, .jsonWithStats:
                return .json
            }
        }
    }

    struct ExportData: Identifiable {
        let id = UUID()
        let content: String
        let filename: String
        let type: UTType
    }

    var body: some View {
        NavigationView {
            Form {
                heartRateSection
                dataExportSection
                sensorLogSection
                exerciseMasterSection
                privacySection
                appInfoSection
            }
            .navigationTitle("設定")
            .sheet(isPresented: $showingMasterDataEditor) {
                ExerciseMasterEditorView()
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView(
                    exportType: $exportType,
                    onExport: performExport
                )
            }
            .sheet(item: $exportData) { data in
                ShareSheet(
                    items: [ExportDocument(data: data.content, filename: data.filename, type: data.type)],
                    onComplete: { success in
                        if success {
                            exportMessage = "エクスポートが完了しました"
                        } else {
                            exportMessage = "エクスポートがキャンセルされました"
                        }
                        showingSuccessAlert = true
                    }
                )
            }
            .alert("エクスポート", isPresented: $showingSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(exportMessage)
            }
            .alert("AirPods非対応", isPresented: $showingAirPodsAlert) {
                Button("OK") { }
            } message: {
                Text("AirPods（第3世代）は心拍数測定に対応していません。Apple WatchまたはBluetooth心拍計をご利用ください。")
            }
            .sheet(item: $sensorExportData) { data in
                ShareSheet(
                    items: [ExportDocument(data: data.content, filename: data.filename, type: data.type)],
                    onComplete: { success in
                        if success {
                            showingSensorExportAlert = true
                            exportMessage = "センサーログをエクスポートしました"
                        }
                    }
                )
            }
            .alert("センサーログ", isPresented: $showingSensorExportAlert) {
                Button("OK") { }
            } message: {
                Text(exportMessage)
            }
            .onAppear {
                isAccelLogging = sensorLogManager.isLogging
            }
        }
    }

    private func performExport() {
        showingExportOptions = false

        let sessionsArray = Array(sessions)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        var content = ""
        var filename = ""

        switch exportType {
        case .csvDetailed:
            content = CSVExporter.export(sessions: sessionsArray)
            filename = "workout_detailed_\(timestamp).csv"
        case .csvSummary:
            content = CSVExporter.exportSummary(sessions: sessionsArray)
            filename = "workout_summary_\(timestamp).csv"
        case .jsonNormal:
            content = JSONExporter.export(sessions: sessionsArray)
            filename = "workout_\(timestamp).json"
        case .jsonWithStats:
            content = JSONExporter.exportWithStatistics(sessions: sessionsArray)
            filename = "workout_stats_\(timestamp).json"
        }

        exportData = ExportData(
            content: content,
            filename: filename,
            type: exportType.contentType
        )
    }

    // MARK: - View Sections

    private var heartRateSection: some View {
        Section(header: Text("心拍数デバイス")) {
            ForEach(HeartRateSourceType.allCases, id: \.self) { source in
                heartRateSourceRow(source: source)
            }

            if heartRateManager.isConnected {
                currentHeartRateRow
            }
        }
    }

    private func heartRateSourceRow(source: HeartRateSourceType) -> some View {
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

    private var currentHeartRateRow: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
            Text("現在の心拍数: \(Int(heartRateManager.currentHeartRate)) bpm")
                .font(.footnote)
        }
    }

    private var dataExportSection: some View {
        Section(header: Text("データエクスポート")) {
            exportButton

            if sessions.isEmpty {
                Text("エクスポート可能なセッションがありません")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                exportDataSummary
            }
        }
    }

    private var exportButton: some View {
        Button(action: { showingExportOptions = true }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)
                Text("ワークアウトデータをエクスポート")
                Spacer()
                if !sessions.isEmpty {
                    Text("\(sessions.count) セッション")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(sessions.isEmpty)
    }

    private var exportDataSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("エクスポート可能なデータ:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("• 合計セッション: \(sessions.count)")
                .font(.caption)
                .foregroundColor(.secondary)

            if let firstSession = sessions.first,
               let lastSession = sessions.last {
                dateRangeText(from: lastSession.startedAt, to: firstSession.startedAt)
            }
        }
        .padding(.top, 4)
    }

    private func dateRangeText(from startDate: Date?, to endDate: Date?) -> some View {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        let start = startDate ?? Date()
        let end = endDate ?? Date()
        return Text("• 期間: \(dateFormatter.string(from: start)) 〜 \(dateFormatter.string(from: end))")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var sensorLogSection: some View {
        Section(header: Text("センサーログ")) {
            // Watch接続状態
            HStack {
                Image(systemName: WatchLink.shared.isWatchReachable ? "applewatch.watchface" : "applewatch.slash")
                    .foregroundColor(WatchLink.shared.isWatchReachable ? .green : .gray)
                Text("Apple Watch")
                Spacer()
                Text(WatchLink.shared.isWatchReachable ? "接続中" : "未接続")
                    .font(.caption)
                    .foregroundColor(WatchLink.shared.isWatchReachable ? .green : .gray)
            }

            // ロギング開始/停止
            HStack {
                if isAccelLogging {
                    Button(action: stopAccelLogging) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("加速度ログ停止")
                        }
                    }
                } else {
                    Button(action: startAccelLogging) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.green)
                            Text("加速度ログ開始")
                        }
                    }
                }
                Spacer()
                if isAccelLogging {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            // サンプリングレート選択
            Picker("サンプリングレート", selection: $selectedAccelRate) {
                Text("25 Hz").tag(25)
                Text("50 Hz").tag(50)
                Text("100 Hz").tag(100)
            }
            .pickerStyle(SegmentedPickerStyle())
            .disabled(isAccelLogging)

            // ログ情報
            if sensorLogManager.sampleCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("記録サンプル数: \(sensorLogManager.sampleCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let lastTime = sensorLogManager.lastSampleTime {
                        Text("最終記録: \(lastTime, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if sensorLogManager.currentLogSize > 0 {
                        Text("ファイルサイズ: \(formatBytes(sensorLogManager.currentLogSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // エクスポートボタン
            Button(action: exportSensorLog) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                    Text("センサーログをエクスポート")
                    Spacer()
                    if sensorLogManager.exportURLsForToday().count > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .disabled(sensorLogManager.exportURLsForToday().isEmpty)

            // 注意事項
            Text("⚠️ 長時間の高レート記録はバッテリーを消費します。通常使用では25-50 Hzを推奨します。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private func startAccelLogging() {
        WatchLink.shared.sendStartLogging(rateHz: selectedAccelRate)
        isAccelLogging = true
    }

    private func stopAccelLogging() {
        WatchLink.shared.sendStopLogging()
        isAccelLogging = false
    }

    private func exportSensorLog() {
        guard let csvData = sensorLogManager.exportDataForToday() else {
            exportMessage = "エクスポート可能なデータがありません"
            showingSensorExportAlert = true
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        let filename = "accelerometer_\(dateString).csv"

        sensorExportData = ExportData(
            content: csvData,
            filename: filename,
            type: .commaSeparatedText
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var exerciseMasterSection: some View {
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
    }

    private var privacySection: some View {
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
    }

    private var appInfoSection: some View {
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

    // MARK: - Actions

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
    @Environment(\.managedObjectContext) var viewContext

    private var dataController: DataController {
        DataController.shared
    }
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
    @Environment(\.managedObjectContext) var viewContext

    private var dataController: DataController {
        DataController.shared
    }
    let exercise: ExerciseMaster

    @State private var name: String = ""
    @State private var selectedCategory: ExerciseCategory = .chest
    @State private var loadUnit: String = ""
    @State private var repsUnit: String = ""
    @State private var defaultLoad: Double = 0
    @State private var defaultReps: Double = 0

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("種目名", text: $name)

                    Picker("カテゴリー", selection: $selectedCategory) {
                        ForEach(ExerciseCategory.allCases) { category in
                            Label {
                                Text(category.displayName)
                            } icon: {
                                Image(systemName: category.icon)
                            }
                            .tag(category)
                        }
                    }
                }

                Section(header: Text("単位設定")) {
                    TextField("負荷単位", text: $loadUnit)
                        .placeholder(when: loadUnit.isEmpty) {
                            Text("例: kg, W, レベル")
                                .foregroundColor(.gray)
                        }

                    TextField("回数単位", text: $repsUnit)
                        .placeholder(when: repsUnit.isEmpty) {
                            Text("例: 回, 秒, 分, セット")
                                .foregroundColor(.gray)
                        }
                }

                Section(header: Text("デフォルト値")) {
                    HStack {
                        Text("負荷:")
                            .frame(width: 60, alignment: .leading)
                        TextField("", value: $defaultLoad, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text(loadUnit.isEmpty ? "単位" : loadUnit)
                            .foregroundColor(loadUnit.isEmpty ? .gray : .primary)
                    }
                    HStack {
                        Text("回数:")
                            .frame(width: 60, alignment: .leading)
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text(repsUnit.isEmpty ? "単位" : repsUnit)
                            .foregroundColor(repsUnit.isEmpty ? .gray : .primary)
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
                    .disabled(name.isEmpty)
                }
            }
        }
        .onAppear {
            name = exercise.name ?? ""
            selectedCategory = ExerciseCategory.from(string: exercise.category ?? "")
            loadUnit = exercise.loadUnit ?? ""
            repsUnit = exercise.repsUnit ?? ""
            defaultLoad = exercise.defaultLoad
            defaultReps = exercise.defaultReps
        }
    }

    private func saveChanges() {
        exercise.name = name
        exercise.category = selectedCategory.rawValue
        exercise.loadUnit = loadUnit
        exercise.repsUnit = repsUnit
        exercise.defaultLoad = defaultLoad
        exercise.defaultReps = defaultReps
        dataController.save()
    }
}

struct AddExerciseView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext

    private var dataController: DataController {
        DataController.shared
    }

    @State private var name: String = ""
    @State private var selectedCategory: ExerciseCategory = .chest
    @State private var loadUnit: String = "kg"
    @State private var repsUnit: String = "回"
    @State private var defaultLoad: Double = 10
    @State private var defaultReps: Double = 10

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本情報")) {
                    TextField("種目名", text: $name)
                        .placeholder(when: name.isEmpty) {
                            Text("例: ベンチプレス")
                                .foregroundColor(.gray)
                        }

                    Picker("カテゴリー", selection: $selectedCategory) {
                        ForEach(ExerciseCategory.allCases) { category in
                            Label {
                                Text(category.displayName)
                            } icon: {
                                Image(systemName: category.icon)
                            }
                            .tag(category)
                        }
                    }
                }

                Section(header: Text("単位設定"), footer: Text("運動に応じた適切な単位を設定してください")) {
                    HStack {
                        Text("負荷単位:")
                            .frame(width: 80, alignment: .leading)
                        TextField("負荷単位", text: $loadUnit)
                            .textFieldStyle(.roundedBorder)
                            .placeholder(when: loadUnit.isEmpty) {
                                Text("例: kg, W, レベル")
                                    .foregroundColor(.gray)
                            }
                    }

                    HStack {
                        Text("回数単位:")
                            .frame(width: 80, alignment: .leading)
                        TextField("回数単位", text: $repsUnit)
                            .textFieldStyle(.roundedBorder)
                            .placeholder(when: repsUnit.isEmpty) {
                                Text("例: 回, 秒, 分, セット")
                                    .foregroundColor(.gray)
                            }
                    }
                }

                Section(header: Text("デフォルト値"), footer: Text("この種目を選択した際の初期値として使用されます")) {
                    HStack {
                        Text("負荷:")
                            .frame(width: 60, alignment: .leading)
                        TextField("", value: $defaultLoad, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text(loadUnit)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("回数:")
                            .frame(width: 60, alignment: .leading)
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text(repsUnit)
                            .foregroundColor(.secondary)
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
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addExercise() {
        let context = dataController.container.viewContext
        let exercise = ExerciseMaster(context: context)
        exercise.id = UUID()
        exercise.name = name
        exercise.category = selectedCategory.rawValue
        exercise.loadUnit = loadUnit
        exercise.repsUnit = repsUnit
        exercise.defaultLoad = defaultLoad
        exercise.defaultReps = defaultReps
        exercise.isActive = true
        dataController.save()
    }
}

// MARK: - Export Views

struct ExportOptionsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var exportType: SettingsView.ExportType
    let onExport: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("エクスポート形式を選択")) {
                    ForEach(SettingsView.ExportType.allCases, id: \.self) { type in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(type.rawValue)
                                    .font(.headline)
                                Text(descriptionForType(type))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if exportType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            exportType = type
                        }
                    }
                }

                Section {
                    Button(action: {
                        dismiss()
                        onExport()
                    }) {
                        HStack {
                            Spacer()
                            Text("エクスポート")
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("エクスポート設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func descriptionForType(_ type: SettingsView.ExportType) -> String {
        switch type {
        case .csvDetailed:
            return "全セットレコードを含む詳細データ"
        case .csvSummary:
            return "セッション単位のサマリーデータ"
        case .jsonNormal:
            return "構造化されたJSONフォーマット"
        case .jsonWithStats:
            return "統計情報を含む完全なJSONデータ"
        }
    }
}