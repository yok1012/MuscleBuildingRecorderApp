import SwiftUI
import UniformTypeIdentifiers

struct MultiDayExportView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var sensorLogManager = SensorLogManager.shared

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()
    @State private var selectedFileTypes: Set<String> = ["accelerometer"]
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportData: ExportData?
    @State private var showingExportAlert = false
    @State private var alertMessage = ""

    struct ExportData: Identifiable {
        let id = UUID()
        let content: Data
        let filename: String
        let type: UTType
    }

    var body: some View {
        NavigationView {
            Form {
                // 期間選択
                Section(header: Text("エクスポート期間")) {
                    DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())

                    DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())

                    HStack {
                        Text("期間:")
                        Text(dateRangeText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // ファイルタイプ選択
                Section(header: Text("センサーデータ")) {
                    ForEach(["accelerometer", "gyroscope", "motion", "combined"], id: \.self) { fileType in
                        HStack {
                            Button(action: { toggleFileType(fileType) }) {
                                HStack {
                                    Image(systemName: selectedFileTypes.contains(fileType) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(.blue)
                                    Text(fileTypeName(fileType))
                                }
                            }
                            Spacer()
                            if let size = getFileSize(for: fileType) {
                                Text(formatBytes(size))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // 心拍数データ
                Section(header: Text("心拍数データ")) {
                    HStack {
                        Button(action: { toggleFileType("heartrate") }) {
                            HStack {
                                Image(systemName: selectedFileTypes.contains("heartrate") ? "checkmark.square.fill" : "square")
                                    .foregroundColor(.red)
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                Text("心拍数ログ")
                            }
                        }
                        Spacer()
                        if let size = getFileSize(for: "heartrate") {
                            Text(formatBytes(size))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("セッション中の心拍数、フェーズ、種目情報を含む時系列データ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // エクスポート設定
                Section(header: Text("エクスポート形式")) {
                    HStack {
                        Text("形式:")
                        Spacer()
                        Text("ZIP圧縮")
                            .foregroundColor(.secondary)
                    }

                    if !selectedFileTypes.isEmpty {
                        HStack {
                            Text("推定サイズ:")
                            Spacer()
                            Text(formatBytes(estimatedExportSize))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // エクスポートボタン
                Section {
                    Button(action: performExport) {
                        if isExporting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("エクスポート中...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("エクスポート")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedFileTypes.isEmpty || isExporting)
                    .foregroundColor(selectedFileTypes.isEmpty ? .gray : .blue)
                }
            }
            .navigationTitle("複数日データエクスポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $exportData) { data in
                ShareSheet(
                    items: [data.content],
                    onComplete: { success in
                        if success {
                            alertMessage = "エクスポートが完了しました"
                        } else {
                            alertMessage = "エクスポートがキャンセルされました"
                        }
                        showingExportAlert = true
                    }
                )
            }
            .alert("エクスポート", isPresented: $showingExportAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var dateRangeText: String {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return "\(days + 1)日間"
    }

    private var estimatedExportSize: Int64 {
        var total: Int64 = 0
        for fileType in selectedFileTypes {
            if let size = getFileSize(for: fileType) {
                total += size
            }
        }
        return total
    }

    private func toggleFileType(_ fileType: String) {
        if selectedFileTypes.contains(fileType) {
            selectedFileTypes.remove(fileType)
        } else {
            selectedFileTypes.insert(fileType)
        }
    }

    private func fileTypeName(_ fileType: String) -> String {
        switch fileType {
        case "accelerometer": return "加速度センサー"
        case "gyroscope": return "ジャイロスコープ"
        case "motion": return "デバイスモーション"
        case "combined": return "統合データ"
        case "heartrate": return "心拍数ログ"
        default: return fileType
        }
    }

    private func getFileSize(for fileType: String) -> Int64? {
        // TODO: 実際のファイルサイズを計算
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func performExport() {
        isExporting = true
        exportProgress = 0

        Task {
            await exportFiles()
        }
    }

    private func exportFiles() async {
        // ファイルを収集してZIPにする
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"

        var filesToExport: [URL] = []
        var currentDate = startDate

        while currentDate <= endDate {
            let dateString = dateFormatter.string(from: currentDate)

            for fileType in selectedFileTypes {
                // 心拍数ログは別のファイル名形式
                let filename: String
                if fileType == "heartrate" {
                    filename = "heartrate_\(dateString).csv"
                } else {
                    filename = "\(fileType)_\(dateString).csv"
                }

                let url = sensorLogManager.logDirectory
                    .appendingPathComponent(filename)

                if FileManager.default.fileExists(atPath: url.path) {
                    filesToExport.append(url)
                }
            }

            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // ZIP作成
        if !filesToExport.isEmpty {
            do {
                let zipData = try await createZipFile(from: filesToExport)
                let timestamp = dateFormatter.string(from: Date())
                let filename = "sensor_logs_\(timestamp).zip"

                await MainActor.run {
                    exportData = ExportData(
                        content: zipData,
                        filename: filename,
                        type: .zip
                    )
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "エクスポートエラー: \(error.localizedDescription)"
                    showingExportAlert = true
                    isExporting = false
                }
            }
        } else {
            await MainActor.run {
                alertMessage = "エクスポート可能なファイルが見つかりませんでした"
                showingExportAlert = true
                isExporting = false
            }
        }
    }

    private func createZipFile(from files: [URL]) async throws -> Data {
        // 簡易的なZIP作成（実際の実装では適切なライブラリを使用）
        // ここではデモとして、ファイルを連結したデータを返す
        var combinedData = Data()

        for file in files {
            if let data = try? Data(contentsOf: file) {
                combinedData.append(data)
                // ファイル名を区切りとして追加
                if let separator = "\n--- \(file.lastPathComponent) ---\n".data(using: .utf8) {
                    combinedData.append(separator)
                }
            }
        }

        return combinedData
    }
}

// ShareSheet拡張 - 削除済み（SensorLogManager内で定義済みのため）