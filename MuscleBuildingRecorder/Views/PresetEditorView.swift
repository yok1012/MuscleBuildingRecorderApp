//
//  PresetEditorView.swift
//  MuscleBuildingRecorder
//
//  プリセット 1 件の編集画面。
//  - タイトル変更
//  - 自動進行 ON/OFF
//  - ステップ（種目）の追加・削除・並び替え・編集
//  - 「実行」ボタン
//

import SwiftUI

struct PresetEditorView: View {
    let presetId: UUID
    @StateObject private var manager = WorkoutPresetManager.shared
    @ObservedObject private var runner = PresetRunner.shared
    @ObservedObject private var sessionManager = SessionManager.shared

    @State private var draft: WorkoutPreset?
    @State private var didLoadDraft = false
    @State private var pendingRunPreset: WorkoutPreset?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let binding = draftBinding {
                editorForm(binding: binding)
            } else {
                Text("プリセットが見つかりません")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(draft?.title ?? "プリセット")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraftIfNeeded)
        .onDisappear(perform: persistIfDirty)
        .alert("セッションが進行中です", isPresented: Binding(
            get: { pendingRunPreset != nil },
            set: { if !$0 { pendingRunPreset = nil } }
        ), presenting: pendingRunPreset) { preset in
            Button("終了して開始", role: .destructive) {
                manager.update(preset)
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

    private var draftBinding: Binding<WorkoutPreset>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft! },
            set: { draft = $0 }
        )
    }

    @ViewBuilder
    private func editorForm(binding: Binding<WorkoutPreset>) -> some View {
        Form {
            titleSection(binding: binding)
            domainSection(binding: binding)
            executionSection(binding: binding)
            stepsSection(binding: binding)
            runSection(preset: binding.wrappedValue)
        }
    }

    @ViewBuilder
    private func domainSection(binding: Binding<WorkoutPreset>) -> some View {
        let currentDomain = binding.wrappedValue.domain
        Section(header: Text("モード"), footer: Text("勉強・仕事モードでは、ステップは「タスク」として扱われます。重量・回数の代わりにタスク名・科目・プロジェクトを設定できます。")) {
            // 現在のモードを大きなバッジで明示
            HStack(spacing: 12) {
                Image(systemName: currentDomain.iconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(domainAccentColor(for: currentDomain))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDomain.displayName + "モード")
                        .font(.headline)
                    Text(currentDomain == .workout ? "セット・回数で記録" : "タスク・時間で記録")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            // モード切替ボタン行（カスタム実装でセグメント描画不具合を回避）
            HStack(spacing: 8) {
                ForEach(ActivityDomain.allCases, id: \.self) { domain in
                    Button {
                        guard binding.wrappedValue.domain != domain else { return }
                        binding.wrappedValue.domain = domain
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: domain.iconName)
                                .font(.title3)
                            Text(domain.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(currentDomain == domain ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(currentDomain == domain ? domainAccentColor(for: domain) : Color(.systemGray5))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func domainAccentColor(for domain: ActivityDomain) -> Color {
        switch domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func titleSection(binding: Binding<WorkoutPreset>) -> some View {
        Section(header: Text("タイトル")) {
            TextField("プリセット名", text: binding.title)
                .textInputAutocapitalization(.never)
        }
    }

    @ViewBuilder
    private func executionSection(binding: Binding<WorkoutPreset>) -> some View {
        Section(header: Text("実行設定"), footer: Text("ON にすると、設定した秒数経過で自動的にフェーズ遷移し、全ステップ完了でセッションも自動終了します。")) {
            Toggle("自動進行", isOn: binding.autoAdvance)
        }
    }

    @ViewBuilder
    private func stepsSection(binding: Binding<WorkoutPreset>) -> some View {
        let domain = binding.wrappedValue.domain
        Section(header: HStack {
            Text(domain == .workout ? "ステップ" : "タスク")
            Spacer()
            Text("\(binding.wrappedValue.steps.count) 件")
                .font(.caption)
                .foregroundColor(.secondary)
        }) {
            ForEach(binding.steps) { stepBinding in
                NavigationLink(destination: PresetStepEditorView(step: stepBinding, domain: domain)) {
                    stepRow(stepBinding.wrappedValue, index: indexOfStep(id: stepBinding.wrappedValue.id, in: binding.wrappedValue), domain: domain)
                }
            }
            .onMove { source, dest in
                binding.wrappedValue.steps.move(fromOffsets: source, toOffset: dest)
            }
            .onDelete { offsets in
                binding.wrappedValue.steps.remove(atOffsets: offsets)
            }

            Button {
                binding.wrappedValue.steps.append(WorkoutPresetStep())
            } label: {
                Label(domain == .workout ? "ステップを追加" : "タスクを追加", systemImage: "plus.circle.fill")
            }
        }
    }

    @ViewBuilder
    private func runSection(preset: WorkoutPreset) -> some View {
        Section {
            Button {
                runPreset(preset)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("このプリセットを実行")
                        .fontWeight(.semibold)
                    Spacer()
                    if preset.autoAdvance {
                        Text("自動進行")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(6)
                    }
                }
            }
            .disabled(!canRun(preset))

            if !canRun(preset) {
                Text(disabledReason(preset))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: WorkoutPresetStep, index: Int, domain: ActivityDomain = .workout) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.headline)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(stepRowTitle(step: step, domain: domain))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(step.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func stepRowTitle(step: WorkoutPresetStep, domain: ActivityDomain) -> String {
        switch domain {
        case .workout:
            return "\(step.category) ・ \(step.exerciseName)"
        case .study:
            let subject = step.subject ?? step.category
            let task = step.taskName ?? step.exerciseName
            return subject.isEmpty ? task : "\(subject) ・ \(task)"
        case .work:
            let project = step.project ?? step.category
            let task = step.taskName ?? step.exerciseName
            return project.isEmpty ? task : "\(project) ・ \(task)"
        }
    }

    // MARK: - Logic

    private func indexOfStep(id: UUID, in preset: WorkoutPreset) -> Int {
        preset.steps.firstIndex(where: { $0.id == id }) ?? 0
    }

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        if let preset = manager.allPresets.first(where: { $0.id == presetId }) {
            draft = preset
        }
    }

    private func persistIfDirty() {
        guard let draft else { return }
        manager.update(draft)
    }

    private func canRun(_ preset: WorkoutPreset) -> Bool {
        !preset.steps.isEmpty && manager.canRun(preset)
    }

    private func disabledReason(_ preset: WorkoutPreset) -> String {
        if preset.steps.isEmpty { return "ステップを 1 件以上追加してください" }
        if !manager.canRun(preset) { return "Pro でロック解除すると実行できます" }
        return ""
    }

    private func runPreset(_ preset: WorkoutPreset) {
        // 編集中の draft を確定保存してから実行
        manager.update(preset)
        if sessionManager.currentPhase == .idle {
            PresetRunner.shared.start(preset: preset, autoAdvance: preset.autoAdvance)
        } else {
            pendingRunPreset = preset
        }
    }
}

// MARK: - Step Editor

struct PresetStepEditorView: View {
    @Binding var step: WorkoutPresetStep
    var domain: ActivityDomain = .workout

    private var availableCategories: [String] {
        let fromMaster = SessionManager.shared.getAvailableCategories()
        if fromMaster.isEmpty {
            return ExerciseCategory.allCases.map { $0.rawValue }
        }
        return fromMaster
    }

    private var availableExercises: [String] {
        SessionManager.shared.getExercises(for: step.category)
    }

    var body: some View {
        Form {
            // ドメイン別の入力UI
            switch domain {
            case .workout:
                workoutInputSection
            case .study:
                studyInputSection
            case .work:
                workInputSection
            }

            Section(header: Text("時間 / 回数")) {
                Stepper(value: $step.workSeconds, in: 5...3600, step: 5) {
                    HStack {
                        Text(domain.workPhaseLabel + "時間")
                        Spacer()
                        Text("\(step.workSeconds) 秒")
                            .foregroundColor(.secondary)
                    }
                }
                Stepper(value: $step.restSeconds, in: 5...3600, step: 5) {
                    HStack {
                        Text(domain.restPhaseLabel + "時間")
                        Spacer()
                        Text("\(step.restSeconds) 秒")
                            .foregroundColor(.secondary)
                    }
                }
                Stepper(value: $step.setCount, in: 1...50, step: 1) {
                    HStack {
                        Text(domain == .workout ? "セット回数" : "サイクル回数")
                        Spacer()
                        Text(domain == .workout ? "\(step.setCount) セット" : "\(step.setCount) サイクル")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 既定値（負荷・回数）は workout のみ
            if domain == .workout {
                Section(header: Text("既定値（任意）"), footer: Text("負荷・回数を指定するとセッション開始時に自動入力されます。")) {
                    HStack {
                        Text("負荷")
                        Spacer()
                        TextField("0", value: Binding(
                            get: { step.defaultLoad ?? 0 },
                            set: { step.defaultLoad = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    }
                    HStack {
                        Text("回数")
                        Spacer()
                        TextField("0", value: Binding(
                            get: { step.defaultReps ?? 0 },
                            set: { step.defaultReps = $0 == 0 ? nil : $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    }
                }
            }

            Section(header: Text("メモ（任意）")) {
                TextField("", text: Binding(
                    get: { step.note ?? "" },
                    set: { step.note = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3, reservesSpace: true)
            }
        }
        .navigationTitle(domain == .workout ? "ステップ編集" : "タスク編集")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var workoutInputSection: some View {
        Section(header: Text("種目")) {
            Picker("カテゴリー", selection: $step.category) {
                ForEach(availableCategories, id: \.self) { cat in
                    Text(cat).tag(cat)
                }
            }
            Picker("種目", selection: $step.exerciseName) {
                ForEach(availableExercises, id: \.self) { name in
                    Text(name).tag(name)
                }
                if availableExercises.isEmpty {
                    Text("種目がありません").tag(step.exerciseName)
                }
            }
            .onChange(of: step.category) { _, _ in
                if let first = availableExercises.first,
                   !availableExercises.contains(step.exerciseName) {
                    step.exerciseName = first
                }
            }
        }
    }

    @ViewBuilder
    private var studyInputSection: some View {
        Section(header: Text("タスク"), footer: Text("勉強モードのタスク名と科目を設定します。")) {
            TextField("タスク名（例: 数学 第3章）", text: Binding(
                get: { step.taskName ?? "" },
                set: { newValue in
                    step.taskName = newValue.isEmpty ? nil : newValue
                    // 内部互換のため、exerciseName にも保存しておく（プリセット実行時のフォールバック先）
                    step.exerciseName = newValue
                }
            ))
            .textInputAutocapitalization(.never)
            TextField("科目（例: 数学）", text: Binding(
                get: { step.subject ?? "" },
                set: { newValue in
                    step.subject = newValue.isEmpty ? nil : newValue
                    step.category = newValue
                }
            ))
            .textInputAutocapitalization(.never)
        }
    }

    @ViewBuilder
    private var workInputSection: some View {
        Section(header: Text("タスク"), footer: Text("仕事モードのタスク名とプロジェクトを設定します。")) {
            TextField("タスク名（例: 提案書レビュー）", text: Binding(
                get: { step.taskName ?? "" },
                set: { newValue in
                    step.taskName = newValue.isEmpty ? nil : newValue
                    step.exerciseName = newValue
                }
            ))
            .textInputAutocapitalization(.never)
            TextField("プロジェクト（例: ProjectA）", text: Binding(
                get: { step.project ?? "" },
                set: { newValue in
                    step.project = newValue.isEmpty ? nil : newValue
                    step.category = newValue
                }
            ))
            .textInputAutocapitalization(.never)
        }
    }
}
