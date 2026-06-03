//
//  ScreenTimeSettingsView.swift
//  MuscleBuildingRecorder
//
//  スクリーンタイム制限機能の設定画面。
//  - 認可リクエスト
//  - 機能 ON/OFF
//  - 除外アプリ選択（警告文付き／デフォルトは電話・メッセージ・ヘルスケアを入れる想定）
//  - Pro: 制限対象アプリ／カテゴリー選択、休憩解除秒数、警告秒数
//

import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

@available(iOS 16.0, *)
struct ScreenTimeSettingsView: View {
    @EnvironmentObject var proUserManager: ProUserManager
    @StateObject private var manager = ScreenTimeManager.shared

    @State private var localConfig = ScreenTimeConfig.load()
    @State private var showingShieldedPicker = false
    @State private var showingExemptionPicker = false
    @State private var isRequestingAuth = false

    var body: some View {
        Form {
            authorizationSection
            if manager.isAuthorized {
                enableSection
                exemptionSection
                if proUserManager.isPro {
                    proShieldTargetSection
                    restUnlockSection
                } else {
                    proUpsellSection
                }
                notesSection
            }
        }
        .navigationTitle("スクリーンタイム制限")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manager.refreshAuthorizationStatus()
            localConfig = manager.config
        }
        .onChange(of: localConfig) { _, newValue in
            manager.updateConfig(newValue)
        }
        .familyActivityPicker(isPresented: $showingShieldedPicker, selection: $localConfig.shieldedSelection)
        .familyActivityPicker(isPresented: $showingExemptionPicker, selection: $localConfig.exemptionSelection)
    }

    // MARK: - Authorization Section
    private var authorizationSection: some View {
        Section(header: Text("認可")) {
            HStack {
                Image(systemName: manager.isAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.isAuthorized ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isAuthorized ? LocalizedStringKey("Screen Time 認可済み") : LocalizedStringKey("認可が必要です"))
                        .font(.headline)
                    Text(manager.isAuthorized
                         ? LocalizedStringKey("アプリの制限を適用できます")
                         : LocalizedStringKey("Apple の Screen Time 認可を得る必要があります"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !manager.isAuthorized {
                Button {
                    Task {
                        isRequestingAuth = true
                        await manager.requestAuthorization()
                        isRequestingAuth = false
                        localConfig = manager.config
                    }
                } label: {
                    HStack {
                        if isRequestingAuth {
                            ProgressView()
                                .padding(.trailing, 6)
                        }
                        Text(isRequestingAuth ? LocalizedStringKey("認可リクエスト中...") : LocalizedStringKey("認可をリクエストする"))
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isRequestingAuth)
            }
        }
    }

    // MARK: - Enable / Disable
    private var enableSection: some View {
        Section {
            Toggle(isOn: $localConfig.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("筋トレ中の制限を有効にする")
                        .font(.headline)
                    Text("セッション開始時に他アプリをシールドします")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Exemption (デフォルトで電話・メッセージ・ヘルスケアを除外する案内)
    private var exemptionSection: some View {
        Section(header: Text("除外するアプリ（制限しない）")) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("緊急時のため、電話・メッセージ・ヘルスケアを除外しておくことを推奨します。")
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                Text("⚠️ 除外しない場合、これらのアプリも制限されます。緊急時に電話がかけられない等のリスクがあるため、必ず初回に設定してください。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button {
                showingExemptionPicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text(exemptionSummary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }

            if hasExemptionSelection {
                Button(role: .destructive) {
                    localConfig.exemptionSelection = FamilyActivitySelection()
                } label: {
                    Label("除外設定をクリア", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var exemptionSummary: String {
        let apps = localConfig.exemptionSelection.applicationTokens.count
        let cats = localConfig.exemptionSelection.categoryTokens.count
        if apps == 0 && cats == 0 {
            return "除外アプリを選択する".localizedSeed
        }
        return "除外: %lldアプリ / %lldカテゴリー".localizedFormat(apps, cats)
    }

    private var hasExemptionSelection: Bool {
        !localConfig.exemptionSelection.applicationTokens.isEmpty ||
        !localConfig.exemptionSelection.categoryTokens.isEmpty
    }

    // MARK: - Pro: Shield target
    private var proShieldTargetSection: some View {
        Section(header: Text("制限対象（Pro）")) {
            Text("指定しない場合は全カテゴリーが制限されます（完全シャットアウト）")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                showingShieldedPicker = true
            } label: {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.red)
                    Text(shieldedSummary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }

            if hasShieldedSelection {
                Button(role: .destructive) {
                    localConfig.shieldedSelection = FamilyActivitySelection()
                } label: {
                    Label("制限対象をクリア（全シャットアウトに戻す）", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var shieldedSummary: String {
        let apps = localConfig.shieldedSelection.applicationTokens.count
        let cats = localConfig.shieldedSelection.categoryTokens.count
        if apps == 0 && cats == 0 {
            return "全カテゴリー（既定）".localizedSeed
        }
        return "制限: %lldアプリ / %lldカテゴリー".localizedFormat(apps, cats)
    }

    private var hasShieldedSelection: Bool {
        !localConfig.shieldedSelection.applicationTokens.isEmpty ||
        !localConfig.shieldedSelection.categoryTokens.isEmpty
    }

    // MARK: - Pro: Rest Unlock
    private var restUnlockSection: some View {
        Section(header: Text("休憩中の一時解除（Pro）")) {
            VStack(alignment: .leading) {
                HStack {
                    Text("解除秒数")
                    Spacer()
                    Text("\(localConfig.restUnlockSeconds) 秒")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
                Slider(
                    value: Binding(
                        get: { Double(localConfig.restUnlockSeconds) },
                        set: { localConfig.restUnlockSeconds = Int($0) }
                    ),
                    in: 15...300, step: 5
                )
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("再ロック前の警告")
                    Spacer()
                    Text("\(localConfig.warnBeforeRelockSeconds) 秒前")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
                Slider(
                    value: Binding(
                        get: { Double(localConfig.warnBeforeRelockSeconds) },
                        set: { localConfig.warnBeforeRelockSeconds = Int($0) }
                    ),
                    in: 0...30, step: 1
                )
            }

            Text("休憩フェーズに入ると指定秒数だけ他アプリが使えます。再ロックの \(localConfig.warnBeforeRelockSeconds) 秒前に通知で警告します。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var proUpsellSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro 版で解放される機能")
                        .font(.headline)
                    Text("• 制限するアプリ／カテゴリーの個別選択\n• 休憩中の一時解除（60秒 既定）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Notes
    private var notesSection: some View {
        Section(header: Text("重要な注意")) {
            VStack(alignment: .leading, spacing: 8) {
                infoRow(icon: "bolt.shield.fill", color: .orange, text: "セッションが idle になった瞬間、またはアプリ復帰時に制限は自動解除されます。")
                infoRow(icon: "hand.raised.fill", color: .red, text: "トレーニング画面の「制限解除」ボタンでいつでも緊急解除できます。")
                infoRow(icon: "phone.fill.arrow.up.right", color: .blue, text: "SOS（緊急通報）は iOS により制限中でも使用可能です。")
            }
        }
    }

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 18)
            Text(LocalizedStringKey(text))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, *)
extension ScreenTimeConfig: Equatable {
    static func == (lhs: ScreenTimeConfig, rhs: ScreenTimeConfig) -> Bool {
        lhs.isEnabled == rhs.isEnabled &&
        lhs.shieldedSelection == rhs.shieldedSelection &&
        lhs.exemptionSelection == rhs.exemptionSelection &&
        lhs.restUnlockSeconds == rhs.restUnlockSeconds &&
        lhs.warnBeforeRelockSeconds == rhs.warnBeforeRelockSeconds &&
        lhs.authorizationGranted == rhs.authorizationGranted
    }
}
