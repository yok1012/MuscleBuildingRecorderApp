import Foundation
import Combine
import SwiftUI

/// 勉強 / 仕事 ドメインで利用するタスクマスタ。
/// ExerciseMaster の study/work 版だが、カテゴリ分割は持たないフラットなリスト。
/// - 保存先: UserDefaults（キー: "taskMasters_<domain>"）
/// - 各エントリは「タスク名 + 科目/プロジェクト + 初期進行度」を保持
struct TaskMaster: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String              // タスク名（必須）
    var subjectOrProject: String  // 科目（study）/ プロジェクト（work）。空可
    var defaultProgress: Double   // 0-100。選択時の初期進行度

    init(
        id: UUID = UUID(),
        name: String,
        subjectOrProject: String = "",
        defaultProgress: Double = 0
    ) {
        self.id = id
        self.name = name
        self.subjectOrProject = subjectOrProject
        self.defaultProgress = defaultProgress
    }
}

final class TaskMasterStore: ObservableObject {
    static let shared = TaskMasterStore()

    /// ドメイン別タスクマスタ配列。SwiftUI 監視用に @Published。
    @Published private(set) var mastersByDomain: [String: [TaskMaster]] = [:]

    private let defaults = UserDefaults.standard

    private init() {
        loadAll()
    }

    // MARK: - CRUD

    func tasks(for domain: String) -> [TaskMaster] {
        mastersByDomain[domain] ?? []
    }

    func addTask(_ task: TaskMaster, for domain: String) {
        var list = tasks(for: domain)
        // 同名 + 同 parent の重複は弾く
        let trimmed = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let parentTrimmed = task.subjectOrProject.trimmingCharacters(in: .whitespacesAndNewlines)
        if list.contains(where: {
            $0.name == trimmed && $0.subjectOrProject == parentTrimmed
        }) {
            return
        }
        var newTask = task
        newTask.name = trimmed
        newTask.subjectOrProject = parentTrimmed
        list.append(newTask)
        save(list, for: domain)
    }

    func updateTask(_ task: TaskMaster, for domain: String) {
        var list = tasks(for: domain)
        guard let idx = list.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subjectOrProject = task.subjectOrProject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        list[idx] = updated
        save(list, for: domain)
    }

    func removeTasks(at offsets: IndexSet, for domain: String) {
        var list = tasks(for: domain)
        list.remove(atOffsets: offsets)
        save(list, for: domain)
    }

    func moveTasks(from source: IndexSet, to destination: Int, for domain: String) {
        var list = tasks(for: domain)
        list.move(fromOffsets: source, toOffset: destination)
        save(list, for: domain)
    }

    // MARK: - Persistence

    private func storageKey(_ domain: String) -> String { "taskMasters_\(domain)" }

    private func loadAll() {
        for domain in ["study", "work"] {
            if let data = defaults.data(forKey: storageKey(domain)),
               let list = try? JSONDecoder().decode([TaskMaster].self, from: data) {
                mastersByDomain[domain] = list
            }
        }
    }

    private func save(_ list: [TaskMaster], for domain: String) {
        mastersByDomain[domain] = list
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: storageKey(domain))
        }
    }
}
