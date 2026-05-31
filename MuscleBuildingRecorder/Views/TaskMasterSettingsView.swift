import SwiftUI

/// ドメイン別タスクマスタの設定画面（追加・編集・削除・並び替え）。
/// 休憩中の TaskMasterSelectionSheet と同じデータを操作するが、こちらは選択せず管理のみ。
struct TaskMasterSettingsView: View {
    let domain: ActivityDomain

    @ObservedObject private var store = TaskMasterStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingAdd = false
    @State private var editingTask: TaskMaster?

    private var domainKey: String { domain.rawValue }

    private var sheetTitle: String {
        switch domain {
        case .study: return "勉強タスクマスタ"
        case .work:  return "仕事タスクマスタ"
        case .workout: return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("登録済みタスク")) {
                    let tasks = store.tasks(for: domainKey)
                    if tasks.isEmpty {
                        Text("タスクはまだありません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(tasks) { task in
                            Button(action: { editingTask = task }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        HStack(spacing: 8) {
                                            if !task.subjectOrProject.isEmpty {
                                                Text(task.subjectOrProject)
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
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                    Button(action: { showingAdd = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("新しいタスクを追加")
                        }
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAdd) {
                TaskMasterEditorView(domain: domain, editing: nil)
            }
            .sheet(item: $editingTask) { task in
                TaskMasterEditorView(domain: domain, editing: task)
            }
        }
    }
}
