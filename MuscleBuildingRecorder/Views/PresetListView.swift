//
//  PresetListView.swift
//  MuscleBuildingRecorder
//
//  ワークアウトプリセット一覧。Pro でなければ先頭 1 件のみ操作可能、
//  残りは「ロック中」として表示するが、データ自体は保持する。
//

import SwiftUI

struct PresetListView: View {
    @StateObject private var manager = WorkoutPresetManager.shared
    @StateObject private var proManager = ProUserManager.shared
    @ObservedObject private var runner = PresetRunner.shared

    @State private var showingPurchaseView = false
    @State private var pendingRunPreset: WorkoutPreset?
    /// 新規作成時にドメイン選択シートを表示するためのフラグ
    @State private var showingDomainPicker = false

    var body: some View {
        Form {
            if runner.isRunning, let active = runner.activePreset {
                runningSection(preset: active)
            }

            availableSection

            if !proManager.isPro && !manager.lockedPresets.isEmpty {
                lockedSection
            }

            infoSection
        }
        .navigationTitle("プリセット")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingDomainPicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!manager.canAddPreset())
            }
        }
        .sheet(isPresented: $showingPurchaseView) {
            PurchaseView()
        }
        .confirmationDialog(
            "どのモードのプリセットを作成しますか？",
            isPresented: $showingDomainPicker,
            titleVisibility: .visible
        ) {
            Button("筋トレ") { createNewPreset(domain: .workout) }
            Button("勉強")   { createNewPreset(domain: .study) }
            Button("仕事")   { createNewPreset(domain: .work) }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("セッションが進行中です", isPresented: Binding(
            get: { pendingRunPreset != nil },
            set: { if !$0 { pendingRunPreset = nil } }
        ), presenting: pendingRunPreset) { preset in
            Button("終了して開始", role: .destructive) {
                PresetRunner.shared.start(preset: preset, autoAdvance: preset.autoAdvance, forceReplaceActiveSession: true)
                pendingRunPreset = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingRunPreset = nil
            }
        } message: { _ in
            Text("現在のセッションを終了して、プリセットを開始しますか？")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func runningSection(preset: WorkoutPreset) -> some View {
        Section(header: Text("実行中")) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.green)
                    Text(preset.title)
                        .font(.headline)
                    Spacer()
                }
                Text(runner.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("自動進行", isOn: Binding(
                    get: { runner.autoAdvanceEnabled },
                    set: { runner.autoAdvanceEnabled = $0 }
                ))
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        Section(header: Text(headerForAvailable)) {
            if manager.allPresets.isEmpty {
                emptyRow
            } else {
                ForEach(manager.accessiblePresets) { preset in
                    NavigationLink(destination: PresetEditorView(presetId: preset.id)) {
                        presetRow(preset, isLocked: false)
                    }
                }
                .onDelete { offsets in
                    manager.delete(at: offsets, in: manager.accessiblePresets)
                }
            }
        }
    }

    private var headerForAvailable: String {
        if proManager.isPro {
            return "プリセット (\(manager.allPresets.count)/\(WorkoutPresetManager.maxPresetCount))"
        }
        return "プリセット"
    }

    @ViewBuilder
    private var lockedSection: some View {
        Section(header: Text("Pro 限定（ロック中）")) {
            ForEach(manager.lockedPresets) { preset in
                presetRow(preset, isLocked: true)
                    .opacity(0.55)
            }
            Button {
                showingPurchaseView = true
            } label: {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Pro でロック解除")
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        Section(footer: footerText) {
            EmptyView()
        }
    }

    private var footerText: some View {
        if proManager.isPro {
            return Text("最大 10 個まで保存できます。タイトルやステップは編集画面から変更可能です。")
        } else {
            return Text("無料プランでは 1 個まで設定・実行できます。Pro にすると以前のプリセットも復活し、最大 10 個まで管理できます。")
        }
    }

    // MARK: - Rows

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("プリセットがまだありません")
                .font(.subheadline)
            Button {
                showingDomainPicker = true
            } label: {
                Label("新規プリセットを作成", systemImage: "plus.circle.fill")
            }
            .disabled(!manager.canAddPreset())
        }
        .padding(.vertical, 4)
    }

    private func domainAccentColor(for domain: ActivityDomain) -> Color {
        switch domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: WorkoutPreset, isLocked: Bool) -> some View {
        HStack(spacing: 10) {
            // ロック中はロックアイコン、それ以外はドメイン別アイコン
            Image(systemName: isLocked ? "lock.fill" : preset.domain.iconName)
                .foregroundColor(isLocked ? .gray : domainAccentColor(for: preset.domain))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(preset.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if preset.autoAdvance {
                    Label("自動進行 ON", systemImage: "forward.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            if !isLocked {
                Button {
                    runPreset(preset)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderless)
                .disabled(preset.steps.isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func createNewPreset(domain: ActivityDomain = .workout) {
        guard manager.canAddPreset() else { return }
        let titlePrefix: String
        let firstStep: WorkoutPresetStep
        switch domain {
        case .workout:
            titlePrefix = "新しいプリセット"
            firstStep = WorkoutPresetStep()
        case .study:
            titlePrefix = "新しい勉強プリセット"
            // study はカテゴリ/種目を空にしておく（PresetStepEditorView で TextField から入力）
            firstStep = WorkoutPresetStep(
                category: "",
                exerciseName: "",
                workSeconds: 25 * 60,  // ポモドーロ風: 25分集中
                restSeconds: 5 * 60,   // 5分休憩
                setCount: 4
            )
        case .work:
            titlePrefix = "新しい仕事プリセット"
            firstStep = WorkoutPresetStep(
                category: "",
                exerciseName: "",
                workSeconds: 50 * 60,  // 50分作業
                restSeconds: 10 * 60,  // 10分休憩
                setCount: 3
            )
        }
        let preset = WorkoutPreset(
            title: titlePrefix,
            steps: [firstStep],
            domain: domain
        )
        manager.add(preset)
    }

    private func runPreset(_ preset: WorkoutPreset) {
        guard manager.canRun(preset), !preset.steps.isEmpty else { return }
        if SessionManager.shared.currentPhase == .idle {
            PresetRunner.shared.start(preset: preset, autoAdvance: preset.autoAdvance)
        } else {
            // 進行中セッションがある場合は確認アラートを表示
            pendingRunPreset = preset
        }
    }
}

// MARK: - Quick Picker (メイン画面のシート用)

/// メインタイマー画面から呼び出される、軽量なプリセット選択シート。
/// 編集機能はなく、選択して即実行するだけ。詳細は「プリセット管理」へ遷移。
struct PresetQuickPickerView: View {
    @StateObject private var manager = WorkoutPresetManager.shared
    @StateObject private var proManager = ProUserManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pendingRunPreset: WorkoutPreset?
    @State private var showingPurchaseView = false

    var body: some View {
        NavigationView {
            Form {
                if manager.accessiblePresets.isEmpty {
                    emptyState
                } else {
                    Section(header: Text("実行できるプリセット")) {
                        ForEach(manager.accessiblePresets) { preset in
                            Button {
                                runPreset(preset)
                            } label: {
                                row(preset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !proManager.isPro && !manager.lockedPresets.isEmpty {
                    Section(header: Text("Pro 限定（ロック中）")) {
                        ForEach(manager.lockedPresets) { preset in
                            row(preset)
                                .opacity(0.55)
                        }
                        Button {
                            showingPurchaseView = true
                        } label: {
                            Label("Pro でロック解除", systemImage: "star.fill")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        PresetListView()
                    } label: {
                        Label("プリセットを管理・編集", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("プリセット選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPurchaseView) {
                PurchaseView()
            }
            .alert("セッションが進行中です", isPresented: Binding(
                get: { pendingRunPreset != nil },
                set: { if !$0 { pendingRunPreset = nil } }
            ), presenting: pendingRunPreset) { preset in
                Button("終了して開始", role: .destructive) {
                    PresetRunner.shared.start(preset: preset, autoAdvance: preset.autoAdvance, forceReplaceActiveSession: true)
                    pendingRunPreset = nil
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {
                    pendingRunPreset = nil
                }
            } message: { _ in
                Text("現在のセッションを終了して、プリセットを開始しますか？")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("プリセットがまだありません")
                    .font(.subheadline)
                NavigationLink(destination: PresetListView()) {
                    Label("プリセットを作成", systemImage: "plus.circle.fill")
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func row(_ preset: WorkoutPreset) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.headline)
                Text(preset.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if preset.autoAdvance {
                    Label("自動進行 ON", systemImage: "forward.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func runPreset(_ preset: WorkoutPreset) {
        guard manager.canRun(preset), !preset.steps.isEmpty else { return }
        if SessionManager.shared.currentPhase == .idle {
            PresetRunner.shared.start(preset: preset, autoAdvance: preset.autoAdvance)
            dismiss()
        } else {
            pendingRunPreset = preset
        }
    }
}
