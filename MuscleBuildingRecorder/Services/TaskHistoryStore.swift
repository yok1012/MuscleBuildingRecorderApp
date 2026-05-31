import Foundation

/// 勉強 / 仕事 ドメインで、subject (科目) や project (プロジェクト) ごとに
/// 過去に入力された taskName の履歴を保持し、サジェストとして再利用するためのストア。
///
/// - 保存先: UserDefaults (JSON エンコード)
/// - キー: "taskHistory_<domain>" 例: "taskHistory_study"
/// - 構造: [parentKey: [taskName]] (最新が先頭)
///   parentKey は study では subject、work では project の文字列
final class TaskHistoryStore {
    static let shared = TaskHistoryStore()

    private let defaults = UserDefaults.standard
    private let maxEntriesPerKey = 10

    private init() {}

    /// 履歴に taskName を追加（最新が先頭）。既存があれば先頭に繰り上げ、上限を超えたら末尾を削除。
    /// - Parameters:
    ///   - domain: "study" / "work"
    ///   - parent: subject (study) / project (work)。空文字なら parent = "" として共通スロットへ保存
    ///   - taskName: 保存するタスク名。空文字は無視
    func remember(domain: String, parent: String, taskName: String) {
        let trimmedTask = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }

        var dict = loadDict(domain: domain)
        let key = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = dict[key] ?? []
        list.removeAll { $0 == trimmedTask }
        list.insert(trimmedTask, at: 0)
        if list.count > maxEntriesPerKey {
            list = Array(list.prefix(maxEntriesPerKey))
        }
        dict[key] = list
        saveDict(dict, domain: domain)
    }

    /// 指定した parent の履歴を取得。parent が空または該当履歴がなければ空配列。
    func suggestions(domain: String, parent: String) -> [String] {
        let dict = loadDict(domain: domain)
        let key = parent.trimmingCharacters(in: .whitespacesAndNewlines)
        return dict[key] ?? []
    }

    /// 全 parent の履歴を取得（subject/project 入力前の汎用サジェスト用途）
    func allKnownParents(domain: String) -> [String] {
        return Array(loadDict(domain: domain).keys).filter { !$0.isEmpty }.sorted()
    }

    // MARK: - Persistence

    private func storageKey(domain: String) -> String { "taskHistory_\(domain)" }

    private func loadDict(domain: String) -> [String: [String]] {
        guard let data = defaults.data(forKey: storageKey(domain: domain)),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveDict(_ dict: [String: [String]], domain: String) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        defaults.set(data, forKey: storageKey(domain: domain))
    }
}
