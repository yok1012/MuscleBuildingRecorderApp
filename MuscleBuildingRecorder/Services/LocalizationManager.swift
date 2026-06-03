//
//  LocalizationManager.swift
//  MuscleBuildingRecorder
//
//  アプリ内言語切替（日本語 / English / システム）を管理する。
//  Bundle.main の localizedString(forKey:value:table:) をスウィズルすることで、
//  SwiftUI の Text(LocalizedStringKey) とコード側の String(localized:) / NSLocalizedString
//  の双方を、アプリ再起動なしで即座に切り替える。
//

import Foundation
import SwiftUI
import Combine
import ObjectiveC

/// アプリがサポートする言語選択肢
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case japanese = "ja"
    case english = "en"

    var id: String { rawValue }

    /// 選択肢の表示名（その言語自身の名称で表示）
    var displayName: String {
        switch self {
        case .system:   return String(localized: "システム", comment: "Language option: follow system setting")
        case .japanese: return "日本語"
        case .english:  return "English"
        }
    }

    /// 該当する .lproj の言語コード。`.system` の場合は nil（端末設定に従う）
    var localeIdentifier: String? {
        switch self {
        case .system:   return nil
        case .japanese: return "ja"
        case .english:  return "en"
        }
    }
}

/// 言語選択状態を保持し、Bundle スウィズルを通じて全文字列の解決言語を切り替える。
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let defaultsKey = "app_language_override"
    private let appGroup = "group.yokAppDev.MuscleBuildingRecorder"

    /// 現在選択中の言語。変更時に永続化＋Bundleへ適用する。
    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            persist()
            apply()
        }
    }

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private init() {
        let raw = (UserDefaults(suiteName: appGroup) ?? .standard).string(forKey: defaultsKey)
        language = AppLanguage(rawValue: raw ?? "") ?? .system
        apply()
    }

    /// 数値・日付フォーマット等に用いる Locale。`.system` なら端末ロケール。
    var locale: Locale {
        if let id = language.localeIdentifier {
            return Locale(identifier: id)
        }
        return Locale.autoupdatingCurrent
    }

    private func persist() {
        sharedDefaults.set(language.rawValue, forKey: defaultsKey)
    }

    private func apply() {
        Bundle.setAppLanguage(language.localeIdentifier)
    }
}

// MARK: - Bundle language override (swizzle)

private var languageBundleKey: UInt8 = 0

/// localizedString を、選択言語の .lproj バンドルへ委譲する Bundle サブクラス。
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Bundle.main の言語を実行時に切り替える。`nil` で端末設定（システム）に戻す。
    static func setAppLanguage(_ language: String?) {
        // Bundle.main を一度だけ LanguageBundle に差し替える
        object_setClass(Bundle.main, LanguageBundle.self)

        let target: Bundle?
        if let language,
           let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            target = Bundle(path: path)
        } else {
            target = nil
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, target, .OBJC_ASSOCIATION_RETAIN)
    }
}
