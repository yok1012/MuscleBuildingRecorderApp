//
//  ScreenTimeConfig.swift
//  MuscleBuildingRecorder
//
//  スクリーンタイム制限機能の設定を永続化するモデル。
//  UserDefaults（App Group）に JSON 化して保存する。
//

import Foundation
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
#endif

@available(iOS 16.0, *)
struct ScreenTimeConfig: Codable {
    /// 機能全体の ON/OFF（OFF の場合はセッション中も shield しない）
    var isEnabled: Bool = false

    /// 追加でシールドしたいアプリ／カテゴリー（Pro ユーザーが選択）。
    /// 空のときは「全カテゴリー shield」を適用する（無料版の完全シャットアウト動作）。
    var shieldedSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// シールドから除外したいアプリ（電話・メッセージ・ヘルスケア等）。
    /// デフォルト除外は「ユーザーが自分で電話等のアプリを選んで入れる」運用にする（システムアプリは
    /// 自動では除外できないため）。
    var exemptionSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// 休憩時にシールド解除する秒数（Pro 限定）。デフォルト 60 秒。
    var restUnlockSeconds: Int = 60

    /// 再ロック何秒前に通知を出すか。デフォルト 10 秒。
    var warnBeforeRelockSeconds: Int = 10

    /// 認可済みフラグ（キャッシュ用）
    var authorizationGranted: Bool = false

    /// UserDefaults 永続化用のキー
    static let storageKey = "screenTimeConfig.v1"

    // MARK: - Persistence
    static func load() -> ScreenTimeConfig {
        guard let data = AppGroupConfig.sharedUserDefaults?.data(forKey: storageKey) else {
            return ScreenTimeConfig()
        }
        do {
            return try JSONDecoder().decode(ScreenTimeConfig.self, from: data)
        } catch {
            print("ScreenTimeConfig: decode failed: \(error)")
            return ScreenTimeConfig()
        }
    }

    func save() {
        guard let defaults = AppGroupConfig.sharedUserDefaults else { return }
        do {
            let data = try JSONEncoder().encode(self)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("ScreenTimeConfig: encode failed: \(error)")
        }
    }
}
