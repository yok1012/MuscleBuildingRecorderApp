import Foundation
import Combine
import SwiftUI

/// ドメイン別のタグプリセットを管理するシングルトン。
/// - 各ドメイン (workout/study/work) でカスタマイズ可能
/// - UserDefaults で永続化（キー: "tagPresets_<domain>"）
/// - 初回起動時は既定タグを返す
final class TagPresetStore: ObservableObject {
    static let shared = TagPresetStore()

    /// ドメイン別タグ配列。SwiftUI 監視用に @Published。
    @Published private(set) var tagsByDomain: [String: [String]] = [:]

    private let defaults = UserDefaults.standard

    static let defaultTagsWorkout = ["重すぎた", "軽すぎた", "左手に痛み", "右手に痛み", "限界"]
    static let defaultTagsStudy   = ["集中できた", "中断あり", "難しかった", "簡単だった", "復習必要"]
    static let defaultTagsWork    = ["順調", "詰まった", "中断あり", "待ち発生", "集中できた"]

    private init() {
        loadAll()
    }

    func tags(for domain: String) -> [String] {
        if let saved = tagsByDomain[domain] { return saved }
        return Self.defaults(for: domain)
    }

    func setTags(_ tags: [String], for domain: String) {
        tagsByDomain[domain] = tags
        save(domain: domain, tags: tags)
    }

    func addTag(_ tag: String, for domain: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = tags(for: domain)
        guard !list.contains(trimmed) else { return }
        list.append(trimmed)
        setTags(list, for: domain)
    }

    func removeTag(at offsets: IndexSet, for domain: String) {
        var list = tags(for: domain)
        list.remove(atOffsets: offsets)
        setTags(list, for: domain)
    }

    func moveTag(from source: IndexSet, to destination: Int, for domain: String) {
        var list = tags(for: domain)
        list.move(fromOffsets: source, toOffset: destination)
        setTags(list, for: domain)
    }

    func resetToDefaults(for domain: String) {
        setTags(Self.defaults(for: domain), for: domain)
    }

    // MARK: - Persistence

    private static func defaults(for domain: String) -> [String] {
        switch domain {
        case "workout": return defaultTagsWorkout
        case "study":   return defaultTagsStudy
        case "work":    return defaultTagsWork
        default:        return []
        }
    }

    private func storageKey(_ domain: String) -> String { "tagPresets_\(domain)" }

    private func loadAll() {
        for domain in ["workout", "study", "work"] {
            if let data = defaults.data(forKey: storageKey(domain)),
               let list = try? JSONDecoder().decode([String].self, from: data) {
                tagsByDomain[domain] = list
            }
        }
    }

    private func save(domain: String, tags: [String]) {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        defaults.set(data, forKey: storageKey(domain))
    }
}
