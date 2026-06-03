import SwiftUI

/// 勉強 / 仕事ドメイン用のタスクマスタ選択シート。
/// ExerciseSelectionSheet の study/work 版だが、カテゴリ分割を持たないフラットリスト。
/// 選択するとタスク名・科目/プロジェクト・初期進行度が SessionManager に反映される。
struct TaskMasterSelectionSheet: View {
    let domain: ActivityDomain

    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject private var store = TaskMasterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddTask = false
    @State private var editingTask: TaskMaster?

    private var domainKey: String { domain.rawValue }

    private var parentLabel: String {
        switch domain {
        case .study: return "科目".localizedSeed
        case .work:  return "プロジェクト".localizedSeed
        case .workout: return ""
        }
    }

    private var accentColor: Color {
        switch domain {
        case .study: return .blue
        case .work:  return .green
        case .workout: return .red
        }
    }

    private var sheetTitle: String {
        "%@タスクを選択".localizedFormat(domain.workPhaseLabel)
    }

    var body: some View {
        NavigationStack {
            List {
                if store.tasks(for: domainKey).isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("マスタタスクがまだありません")
                                .font(.headline)
                            Text("右上の「+」からよく使うタスクを登録すると、休憩中の入力で素早く選択できます。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section(header: Text("登録済みタスク")) {
                        ForEach(store.tasks(for: domainKey)) { task in
                            HStack {
                                Button(action: { apply(task) }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        HStack(spacing: 8) {
                                            if !task.subjectOrProject.isEmpty {
                                                Label(task.subjectOrProject, systemImage: domain.iconName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            if task.defaultProgress > 0 {
                                                Text("初期 \(Int(task.defaultProgress))%")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if isCurrentlyApplied(task) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(accentColor)
                                }
                                Button {
                                    editingTask = task
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            store.removeTasks(at: offsets, for: domainKey)
                        }
                        .onMove { source, dest in
                            store.moveTasks(from: source, to: dest, for: domainKey)
                        }
                    }
                }

                Section {
                    Button(action: { showingAddTask = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("新しいタスクを追加")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        EditButton()
                        Button(action: { showingAddTask = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                TaskMasterEditorView(domain: domain, editing: nil)
            }
            .sheet(item: $editingTask) { task in
                TaskMasterEditorView(domain: domain, editing: task)
            }
        }
    }

    private func isCurrentlyApplied(_ task: TaskMaster) -> Bool {
        let currentParent = domain == .study ? sessionManager.currentSubject : sessionManager.currentProject
        return sessionManager.currentTaskName == task.name && currentParent == task.subjectOrProject
    }

    private func apply(_ task: TaskMaster) {
        switch domain {
        case .study:
            sessionManager.currentSubject = task.subjectOrProject
        case .work:
            sessionManager.currentProject = task.subjectOrProject
        case .workout:
            break
        }
        sessionManager.currentTaskName = task.name
        if task.defaultProgress > 0 {
            sessionManager.currentProgress = task.defaultProgress
        }
        if let record = sessionManager.currentSetRecord {
            record.taskName = task.name.isEmpty ? nil : task.name
            record.focusScore = sessionManager.currentProgress
        }
        if !task.name.isEmpty {
            TaskHistoryStore.shared.remember(
                domain: domainKey,
                parent: task.subjectOrProject,
                taskName: task.name
            )
        }
        dismiss()
    }
}

/// マスタタスクの追加・編集用 Form。
struct TaskMasterEditorView: View {
    let domain: ActivityDomain
    let editing: TaskMaster?

    @ObservedObject private var store = TaskMasterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var parent: String = ""
    @State private var defaultProgress: Double = 0

    private var parentLabel: String {
        switch domain {
        case .study: return "科目".localizedSeed
        case .work:  return "プロジェクト".localizedSeed
        case .workout: return ""
        }
    }

    private var parentPlaceholder: String {
        switch domain {
        case .study: return "例: 数学 / 英語".localizedSeed
        case .work:  return "例: ProjectA".localizedSeed
        case .workout: return ""
        }
    }

    private var taskPlaceholder: String {
        switch domain {
        case .study: return "例: 第3章 演習問題".localizedSeed
        case .work:  return "例: 提案書レビュー".localizedSeed
        case .workout: return ""
        }
    }

    private var navTitle: String {
        editing == nil ? "タスクを追加".localizedSeed : "タスクを編集".localizedSeed
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("タスク名")) {
                    TextField(taskPlaceholder, text: $name)
                        .textInputAutocapitalization(.never)
                }
                Section(header: Text(parentLabel + "（任意）")) {
                    TextField(parentPlaceholder, text: $parent)
                        .textInputAutocapitalization(.never)
                }
                Section(header: Text("初期進行度")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("進行度")
                            Spacer()
                            Text("\(Int(defaultProgress))%")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .monospacedDigit()
                        }
                        Slider(value: $defaultProgress, in: 0...100, step: 1)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editing == nil ? "追加" : "保存") { save() }
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let task = editing {
                    name = task.name
                    parent = task.subjectOrProject
                    defaultProgress = task.defaultProgress
                }
            }
        }
    }

    private func save() {
        if var task = editing {
            task.name = name
            task.subjectOrProject = parent
            task.defaultProgress = defaultProgress
            store.updateTask(task, for: domain.rawValue)
        } else {
            let task = TaskMaster(
                name: name,
                subjectOrProject: parent,
                defaultProgress: defaultProgress
            )
            store.addTask(task, for: domain.rawValue)
        }
        dismiss()
    }
}
