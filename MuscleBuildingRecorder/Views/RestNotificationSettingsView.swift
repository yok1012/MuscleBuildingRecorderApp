import SwiftUI

/// 休憩通知設定画面
struct RestNotificationSettingsView: View {
    @StateObject private var widgetStateStore = WidgetStateStore.shared
    @StateObject private var notificationScheduler = RestNotificationScheduler.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                // 通知許可セクション
                notificationAuthorizationSection

                // 通知設定セクション（3種類）
                ForEach(widgetStateStore.restNotificationSettings.indices, id: \.self) { index in
                    notificationSettingSection(index: index)
                }

                // 説明セクション
                infoSection
            }
            .navigationTitle("休憩通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Notification Authorization Section
    private var notificationAuthorizationSection: some View {
        Section {
            HStack {
                Image(systemName: notificationScheduler.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(notificationScheduler.isAuthorized ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("通知許可")
                        .font(.headline)
                    Text(notificationScheduler.isAuthorized ? LocalizedStringKey("通知が許可されています") : LocalizedStringKey("通知を許可してください"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !notificationScheduler.isAuthorized {
                    Button("許可する") {
                        Task {
                            _ = try? await notificationScheduler.requestAuthorization()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("通知設定")
        }
    }

    // MARK: - Individual Notification Setting Section
    private func notificationSettingSection(index: Int) -> some View {
        let setting = widgetStateStore.restNotificationSettings[index]

        return Section {
            // 有効/無効トグル
            Toggle(isOn: Binding(
                get: { setting.isEnabled },
                set: { newValue in
                    var updated = setting
                    updated.isEnabled = newValue
                    widgetStateStore.updateRestNotificationSetting(at: index, setting: updated)
                }
            )) {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(setting.isEnabled ? notificationColor(for: index) : .gray)
                    Text("通知 \(index + 1)")
                }
            }

            if setting.isEnabled {
                // 時間設定
                HStack {
                    Text("通知タイミング")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { setting.timeSeconds },
                        set: { newValue in
                            var updated = setting
                            updated.timeSeconds = newValue
                            widgetStateStore.updateRestNotificationSetting(at: index, setting: updated)
                        }
                    )) {
                        ForEach(timeOptions, id: \.self) { seconds in
                            Text(formatTimeOption(seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // バイブレーション回数
                Stepper(value: Binding(
                    get: { setting.vibrationCount },
                    set: { newValue in
                        var updated = setting
                        updated.vibrationCount = max(1, min(5, newValue))
                        widgetStateStore.updateRestNotificationSetting(at: index, setting: updated)
                    }
                ), in: 1...5) {
                    HStack {
                        Text("振動回数")
                        Spacer()
                        Text("\(setting.vibrationCount) 回")
                            .foregroundColor(.secondary)
                    }
                }

                // サウンド設定
                Toggle(isOn: Binding(
                    get: { setting.soundEnabled },
                    set: { newValue in
                        var updated = setting
                        updated.soundEnabled = newValue
                        widgetStateStore.updateRestNotificationSetting(at: index, setting: updated)
                    }
                )) {
                    Text("サウンド")
                }
            }
        } header: {
            Text("通知 \(index + 1): \(setting.timeDisplayString)")
        } footer: {
            if setting.isEnabled {
                Text("休憩開始から\(setting.timeDisplayString)後に\(setting.vibrationCount)回振動します")
            }
        }
    }

    // MARK: - Info Section
    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("使い方", systemImage: "info.circle")
                    .font(.headline)

                Text("休憩フェーズが始まると、設定した時間に通知が届きます。次のセットを始めるタイミングの目安にしてください。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("振動回数を増やすと、より強く注意を引くことができます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helper Properties
    private var timeOptions: [Int] {
        [15, 30, 45, 60, 90, 120, 180]
    }

    private func formatTimeOption(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds > 0 {
                return "%lld分%lld秒".localizedFormat(minutes, remainingSeconds)
            }
            return "%lld分".localizedFormat(minutes)
        }
        return "%lld秒".localizedFormat(seconds)
    }

    private func notificationColor(for index: Int) -> Color {
        switch index {
        case 0: return .green
        case 1: return .orange
        case 2: return .red
        default: return .blue
        }
    }
}

// MARK: - Heart Rate Zone Settings View
struct HeartRateZoneSettingsView: View {
    @StateObject private var widgetStateStore = WidgetStateStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var age: Int = 30
    @State private var useCustomMaxHR: Bool = false
    @State private var customMaxHR: Double = 190

    var body: some View {
        NavigationView {
            Form {
                // 年齢設定
                Section {
                    Stepper(value: $age, in: 10...100) {
                        HStack {
                            Text("年齢")
                            Spacer()
                            Text("\(age) 歳")
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: age) {
                        saveSettings()
                    }

                    HStack {
                        Text("推定最大心拍数")
                        Spacer()
                        Text("\(220 - age) bpm")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("基本設定")
                } footer: {
                    Text("最大心拍数は「220 - 年齢」で計算されます")
                }

                // カスタム最大心拍数
                Section {
                    Toggle("カスタム最大心拍数を使用", isOn: $useCustomMaxHR)
                        .onChange(of: useCustomMaxHR) {
                            saveSettings()
                        }

                    if useCustomMaxHR {
                        Stepper(value: $customMaxHR, in: 100...220, step: 1) {
                            HStack {
                                Text("最大心拍数")
                                Spacer()
                                Text("\(Int(customMaxHR)) bpm")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: customMaxHR) {
                            saveSettings()
                        }
                    }
                } footer: {
                    Text("実測した最大心拍数がある場合は、より正確なゾーン表示ができます")
                }

                // ゾーン表示
                Section {
                    ForEach(HeartRateZone.allCases, id: \.self) { zone in
                        let range = calculateHeartRateRange(for: zone)
                        HStack {
                            Circle()
                                .fill(zone.color)
                                .frame(width: 12, height: 12)
                            Text(zone.displayName)
                                .fontWeight(.medium)
                            Text("(\(zone.description))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(range.lowerBound) - \(range.upperBound) bpm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("心拍ゾーン")
                }
            }
            .navigationTitle("心拍ゾーン設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }

    private var maxHeartRate: Double {
        useCustomMaxHR ? customMaxHR : Double(220 - age)
    }

    private func calculateHeartRateRange(for zone: HeartRateZone) -> ClosedRange<Int> {
        let range = zone.percentageRange
        let lower = Int(maxHeartRate * range.lowerBound)
        let upper = Int(maxHeartRate * range.upperBound)
        return lower...upper
    }

    private func loadSettings() {
        let settings = widgetStateStore.heartRateZoneSettings
        age = settings.age
        useCustomMaxHR = settings.customMaxHeartRate != nil
        customMaxHR = settings.customMaxHeartRate ?? Double(220 - settings.age)
    }

    private func saveSettings() {
        let settings = HeartRateZoneSettings(
            age: age,
            customMaxHeartRate: useCustomMaxHR ? customMaxHR : nil
        )
        widgetStateStore.saveHeartRateZoneSettings(settings)
    }
}

#Preview {
    RestNotificationSettingsView()
}
