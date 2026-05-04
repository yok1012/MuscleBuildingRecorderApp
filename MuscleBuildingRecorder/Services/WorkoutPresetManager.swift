//
//  WorkoutPresetManager.swift
//  MuscleBuildingRecorder
//
//  ワークアウトプリセットの CRUD と Pro 制限の管理。
//  - データは常に全件保存（Pro 解除でも消さない → Pro 復活時に復元）
//  - 表示・実行可能な範囲は accessiblePresets / canAddPreset で制限
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class WorkoutPresetManager: ObservableObject {
    static let shared = WorkoutPresetManager()

    /// プリセット最大数（Pro 時の上限）
    static let maxPresetCount = 10
    /// App Group UserDefaults の保存キー
    static let storageKey = "workoutPresetStore.v1"

    @Published private(set) var allPresets: [WorkoutPreset] = []

    private var proStatusObserver: NSObjectProtocol?

    private init() {
        load()
        // Pro 状態が変わったら表示が変わるので objectWillChange を発火
        proStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ProStatusChanged"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                WorkoutPresetManager.shared.objectWillChange.send()
            }
        }
    }

    deinit {
        if let observer = proStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Pro 制限

    var isPro: Bool {
        ProUserManager.shared.isPro
    }

    /// 表示・実行可能なプリセット（無料は先頭 1 件のみ）
    var accessiblePresets: [WorkoutPreset] {
        isPro ? allPresets : Array(allPresets.prefix(1))
    }

    /// Pro 限定でロックされているプリセット（無料時のみ非空）
    var lockedPresets: [WorkoutPreset] {
        isPro ? [] : Array(allPresets.dropFirst())
    }

    /// プリセットを新規追加できるか
    func canAddPreset() -> Bool {
        if isPro {
            return allPresets.count < Self.maxPresetCount
        }
        return allPresets.isEmpty
    }

    /// プリセットを実行できるか（無料はアクセス可能な範囲＝先頭 1 件のみ）
    func canRun(_ preset: WorkoutPreset) -> Bool {
        accessiblePresets.contains(where: { $0.id == preset.id })
    }

    // MARK: - CRUD

    @discardableResult
    func add(_ preset: WorkoutPreset) -> Bool {
        guard canAddPreset() else { return false }
        var p = preset
        p.updatedAt = Date()
        allPresets.append(p)
        save()
        return true
    }

    func update(_ preset: WorkoutPreset) {
        guard let index = allPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        var p = preset
        p.updatedAt = Date()
        allPresets[index] = p
        save()
    }

    func delete(id: UUID) {
        allPresets.removeAll { $0.id == id }
        save()
    }

    func delete(at offsets: IndexSet, in presets: [WorkoutPreset]) {
        let idsToDelete = offsets.compactMap { presets.indices.contains($0) ? presets[$0].id : nil }
        allPresets.removeAll { idsToDelete.contains($0.id) }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        allPresets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func rename(id: UUID, to title: String) {
        guard let index = allPresets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        allPresets[index].title = trimmed
        allPresets[index].updatedAt = Date()
        save()
    }

    @discardableResult
    func duplicate(id: UUID) -> WorkoutPreset? {
        guard canAddPreset(),
              let preset = allPresets.first(where: { $0.id == id }) else { return nil }
        var copy = preset
        copy.id = UUID()
        copy.title = "\(preset.title) のコピー"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.steps = copy.steps.map { step in
            var s = step
            s.id = UUID()
            return s
        }
        allPresets.append(copy)
        save()
        return copy
    }

    // MARK: - Persistence

    private func save() {
        guard let defaults = AppGroupConfig.sharedUserDefaults else {
            print("WorkoutPresetManager: ❌ App Group UserDefaults unavailable")
            return
        }
        let store = WorkoutPresetStore(presets: allPresets)
        do {
            let data = try JSONEncoder().encode(store)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("WorkoutPresetManager: encode failed: \(error)")
        }
    }

    private func load() {
        guard let defaults = AppGroupConfig.sharedUserDefaults,
              let data = defaults.data(forKey: Self.storageKey) else {
            allPresets = []
            return
        }
        do {
            let store = try JSONDecoder().decode(WorkoutPresetStore.self, from: data)
            // 将来 schemaVersion による分岐マイグレーションをここで実施
            allPresets = store.presets
        } catch {
            print("WorkoutPresetManager: decode failed: \(error)")
            allPresets = []
        }
    }
}
