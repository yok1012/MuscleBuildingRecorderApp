import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var heartRateManager: HeartRateManager
    @StateObject private var proUserManager = ProUserManager.shared
    @StateObject private var presetManager = WorkoutPresetManager.shared
    @ObservedObject private var sessionManager = SessionManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @Environment(\.managedObjectContext) var viewContext
    @State private var selectedHeartRateSource: HeartRateSourceType = .healthKit
    @State private var showingBLEDeviceSelector = false
    @State private var showingMasterDataEditor = false
    @State private var showingExportOptions = false
    @State private var exportType: ExportType = .csvDetailed
    @State private var showingExporter = false
    @State private var exportData: ExportData?
    @State private var showingSuccessAlert = false
    @State private var exportMessage = ""
    @State private var showingPurchaseView = false

    // センサーログ関連の状態
    @StateObject private var sensorLogManager = SensorLogManager.shared
    @State private var isAccelLogging = false
    @State private var selectedAccelRate = 50
    @State private var showingSensorExportAlert = false
    @State private var sensorExportData: ExportData?
    @State private var enabledSensors: Set<String> = ["accel"]
    @State private var showingMultiDayExport = false
    @State private var exportDateRange: ClosedRange<Date> = Date()...Date()

    // 通知・心拍ゾーン設定
    @State private var showingRestNotificationSettings = false
    @State private var showingHeartRateZoneSettings = false
    @State private var showingTagPresetSettings = false
    @State private var showingTaskMasterStudy = false
    @State private var showingTaskMasterWork = false
    /// 完了後ヒント画面の表示可否（false = 表示する）
    @AppStorage("hideCompletionTips") private var hideCompletionTips = false

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
                proSection
                screenTimeSection
                workoutBehaviorSection
                buttonLayoutSection
                presetsSection
                heartRateSection
                notificationSettingsSection
                dataExportSection
                #if DEBUG
                sensorLogSection
                #endif
                privacySection
                languageSection
                appInfoSection
                resetDataSection
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
            .sheet(isPresented: $showingBLEDeviceSelector) {
                BLEDeviceSelectorView(bleService: heartRateManager.bleService)
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
            .sheet(isPresented: $showingMultiDayExport) {
                MultiDayExportView()
            }
            .sheet(isPresented: $showingPurchaseView) {
                PurchaseView()
            }
            .sheet(isPresented: $showingRestNotificationSettings) {
                RestNotificationSettingsView()
            }
            .sheet(isPresented: $showingHeartRateZoneSettings) {
                HeartRateZoneSettingsView()
            }
            .sheet(isPresented: $showingTagPresetSettings) {
                TagPresetSettingsView()
            }
            .sheet(isPresented: $showingTaskMasterStudy) {
                TaskMasterSettingsView(domain: .study)
            }
            .sheet(isPresented: $showingTaskMasterWork) {
                TaskMasterSettingsView(domain: .work)
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
            // Apple Watch (HealthKit)
            healthKitRow

            // Bluetooth心拍計
            bluetoothRow

            // 現在の心拍数
            if heartRateManager.currentHeartRate > 0 {
                currentHeartRateRow
            }
        }
    }

    private var healthKitRow: some View {
        HStack {
            Image(systemName: "applewatch")
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text("Apple Watch (HealthKit)")
                    .font(.headline)
                Text(heartRateManager.activeHeartRateSource.localizedSeed)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if heartRateManager.isUsingWatchHeartRate || heartRateManager.isStandaloneMode {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private var bluetoothRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.circle")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading) {
                    Text("Bluetooth心拍計")
                        .font(.headline)
                    Text(bluetoothStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if heartRateManager.bleService.connectionState == .connected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // 接続中のデバイス情報
            if let deviceName = heartRateManager.bleService.connectedDeviceName {
                HStack {
                    Spacer().frame(width: 38)
                    HStack {
                        Image(systemName: "link")
                            .font(.caption)
                        Text(deviceName)
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    Spacer()

                    // 切断ボタン
                    Button(action: {
                        heartRateManager.bleService.disconnect()
                    }) {
                        Text("切断")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // デバイス選択・再接続ボタン
            HStack {
                Spacer().frame(width: 38)

                if heartRateManager.bleService.savedDeviceUUID != nil && heartRateManager.bleService.connectionState == .disconnected {
                    Button(action: reconnectBLE) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("再接続")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: { showingBLEDeviceSelector = true }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text(heartRateManager.bleService.connectedDeviceName == nil ? LocalizedStringKey("デバイスを検索") : LocalizedStringKey("別のデバイス"))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var bluetoothStatusText: String {
        switch heartRateManager.bleService.connectionState {
        case .disconnected:
            if heartRateManager.bleService.savedDeviceUUID != nil {
                return "未接続（保存済みデバイスあり）".localizedSeed
            }
            return "未接続".localizedSeed
        case .connecting:
            return "接続中...".localizedSeed
        case .discovering:
            return "サービス検出中...".localizedSeed
        case .connected:
            return "接続済み".localizedSeed
        }
    }

    private func reconnectBLE() {
        Task {
            do {
                try await heartRateManager.bleService.reconnect()
            } catch {
                print("BLE reconnection failed: \(error)")
            }
        }
    }

    private var currentHeartRateRow: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
            Text("現在の心拍数: \(Int(heartRateManager.currentHeartRate)) bpm")
                .font(.footnote)
            Spacer()
            Text(heartRateManager.activeHeartRateSource)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Workout Behavior Section
    private var workoutBehaviorSection: some View {
        Section(header: Text("トレーニング動作")) {
            Toggle(isOn: $sessionManager.confirmTransitionToWork) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("筋トレ移行時に確認")
                        .font(.headline)
                    Text("休憩から筋トレに戻るとき、回数・重量を確認するダイアログを表示します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Toggle(isOn: Binding(
                get: { !hideCompletionTips },
                set: { hideCompletionTips = !$0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完了後にヒントを表示")
                        .font(.headline)
                    Text("セッション完了後にアプリの使い方ヒントを表示します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Button(action: { showingTagPresetSettings = true }) {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.yellow)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("タグの管理")
                            .font(.headline)
                        Text("休憩中のクイック入力で選べるタグをドメイン別にカスタマイズ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            Button(action: { showingMasterDataEditor = true }) {
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(.red)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("エクササイズマスタ")
                            .font(.headline)
                        Text("筋トレの種目を登録・編集")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            Button(action: { showingTaskMasterStudy = true }) {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("勉強タスクマスタ")
                            .font(.headline)
                        Text("よく使う勉強タスクを登録して、休憩中に素早く選択")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            Button(action: { showingTaskMasterWork = true }) {
                HStack {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(.green)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("仕事タスクマスタ")
                            .font(.headline)
                        Text("よく使う仕事タスクを登録して、休憩中に素早く選択")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
        }
    }

    // MARK: - Notification Settings Section
    private var notificationSettingsSection: some View {
        Section(header: Text("通知・ゾーン設定")) {
            // 休憩通知設定
            Button(action: { showingRestNotificationSettings = true }) {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundColor(.orange)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("休憩通知設定")
                            .font(.headline)
                        Text("インターバル終了のリマインダー")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            // 心拍ゾーン設定
            Button(action: { showingHeartRateZoneSettings = true }) {
                HStack {
                    Image(systemName: "heart.text.square")
                        .foregroundColor(.red)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("心拍ゾーン設定")
                            .font(.headline)
                        Text("年齢・最大心拍数の設定")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)
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
                Text(WatchLink.shared.isWatchReachable ? LocalizedStringKey("接続中") : LocalizedStringKey("未接続"))
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

            // センサー選択
            VStack(alignment: .leading, spacing: 8) {
                Text("記録するセンサー")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    ForEach(["accel", "gyro", "motion"], id: \.self) { sensor in
                        Button(action: { toggleSensor(sensor) }) {
                            HStack(spacing: 4) {
                                Image(systemName: enabledSensors.contains(sensor) ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                Text(sensorName(sensor))
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(enabledSensors.contains(sensor) ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .disabled(isAccelLogging)
                    }
                }
            }

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
                    Text("本日のログをエクスポート")
                    Spacer()
                    if sensorLogManager.exportURLsForToday().count > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            .disabled(sensorLogManager.exportURLsForToday().isEmpty)

            // 複数日エクスポート
            Button(action: { showingMultiDayExport = true }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("複数日のデータをエクスポート")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            // リアルタイムグラフ
            NavigationLink(destination: SensorGraphView()) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.green)
                    Text("リアルタイムグラフを表示")
                    Spacer()
                }
            }
            .disabled(!isAccelLogging)

            // 注意事項
            Text("⚠️ 長時間の高レート記録はバッテリーを消費します。通常使用では25-50 Hzを推奨します。")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private func startAccelLogging() {
        WatchLink.shared.sendStartLogging(rateHz: selectedAccelRate, sensors: enabledSensors)
        isAccelLogging = true
    }

    private func toggleSensor(_ sensor: String) {
        if enabledSensors.contains(sensor) {
            enabledSensors.remove(sensor)
        } else {
            enabledSensors.insert(sensor)
        }
        // motionを選択したら他も自動的に選択
        if sensor == "motion" && enabledSensors.contains("motion") {
            enabledSensors.insert("accel")
            enabledSensors.insert("gyro")
        }
    }

    private func sensorName(_ sensor: String) -> String {
        switch sensor {
        case "accel": return "加速度"
        case "gyro": return "ジャイロ"
        case "motion": return "姿勢"
        default: return sensor
        }
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

    private var resetDataSection: some View {
        Section(header: Text("データ初期化")) {
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

    // MARK: - Language Section
    private var languageSection: some View {
        Section(header: Text("言語")) {
            Picker(selection: $localizationManager.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundColor(.blue)
                    Text("言語")
                }
            }
            .pickerStyle(.menu)
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

    // MARK: - Screen Time Section
    @ViewBuilder
    private var screenTimeSection: some View {
        if #available(iOS 16.0, *) {
            Section(header: Text("スクリーンタイム制限")) {
                NavigationLink(destination: ScreenTimeSettingsView()
                    .environmentObject(proUserManager)) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("筋トレ中の他アプリ制限")
                                .font(.headline)
                            Text("セッション中は他アプリを自動でシールド。Proで選択や休憩解除が可能")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Button Layout Section (Pro)
    private var buttonLayoutSection: some View {
        Section(header: Text("ボタン配置")) {
            NavigationLink(destination: ButtonLayoutSettingsView()
                .environmentObject(proUserManager)) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group")
                        .foregroundColor(.purple)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("メイン切替ボタンの位置")
                                .font(.headline)
                            if !proUserManager.isPro {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        Text("休憩切替ボタンを上部・中部・下部から選べます (Pro)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Workout Presets Section
    private var presetsSection: some View {
        Section(header: Text("ワークアウトプリセット")) {
            NavigationLink(destination: PresetListView()) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("プリセット管理")
                                .font(.headline)
                            if !proUserManager.isPro && presetManager.allPresets.count > 1 {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        Text(presetSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var presetSubtitle: String {
        let count = presetManager.allPresets.count
        if count == 0 {
            return "種目・時間・セット数を順に並べて自動進行 (無料: 1個・Pro: 最大10個)".localizedSeed
        }
        return "%lld 件保存済み (無料: 1個・Pro: 最大10個)".localizedFormat(count)
    }

    // MARK: - Pro Section
    private var proSection: some View {
        Section(header: Text("Pro版")) {
            if proUserManager.isPro {
                // Pro版購入済み
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pro版 有効")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("広告なしでお楽しみいただけます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                // Pro版未購入
                Button(action: { showingPurchaseView = true }) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pro版にアップグレード")
                                .font(.headline)
                            Text("広告なしでトレーニングに集中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }

            #if DEBUG
            // デバッグ用：Pro状態をトグル
            Button(action: {
                proUserManager.debugSetPro(!proUserManager.isPro)
            }) {
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(.orange)
                    Text("DEBUG: Pro状態をトグル")
                        .foregroundColor(.orange)
                }
            }
            #endif
        }
    }

    // MARK: - Actions

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
                    Section(header: Text(group.category.localizedSeed)) {
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
            Text((exercise.name ?? "").localizedSeed)
                .font(.headline)
            HStack {
                Text("デフォルト: \(exercise.defaultLoad, specifier: "%.1f") \((exercise.loadUnit ?? "").localizedSeed)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("×")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(exercise.defaultReps, specifier: "%.0f") \((exercise.repsUnit ?? "").localizedSeed)")
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
                        Text(loadUnit.isEmpty ? "単位".localizedSeed : loadUnit)
                            .foregroundColor(loadUnit.isEmpty ? .gray : .primary)
                    }
                    HStack {
                        Text("回数:")
                            .frame(width: 60, alignment: .leading)
                        TextField("", value: $defaultReps, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                        Text(repsUnit.isEmpty ? "単位".localizedSeed : repsUnit)
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