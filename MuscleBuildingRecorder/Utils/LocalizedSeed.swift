//
//  LocalizedSeed.swift
//  MuscleBuildingRecorder
//
//  既定 seed データ（種目名・カテゴリ・単位・タグ等）を「表示時」にローカライズする。
//  これらは Core Data / UserDefaults に日本語文字列として保存される「データ」であり、
//  SwiftUI の自動ローカライズ対象にならない。保存値（＝キー）はそのままに、
//  表示直前に現在の言語の翻訳へ変換する。
//
//  - xcstrings に登録済みの既定値 → 翻訳を返す
//  - 未登録（ユーザーが自由入力した値）→ 元の文字列をそのまま返す
//
//  Bundle.main.localizedString(forKey:value:table:) を経由するため、
//  LocalizationManager のアプリ内言語切替（Bundle スウィズル）にも追従する。
//

import Foundation

extension String {
    /// 既定 seed データ・動的表示文字列の表示用ローカライズ値。未登録値は自身を返す。
    ///
    /// 重要: `String(localized:)` は LocalizationManager の Bundle スウィズル
    /// （アプリ内言語切替）を **無視する** ため、`Text(変数)` 等で表示する動的な
    /// String には必ずこの経路（Bundle.main.localizedString）を使うこと。
    var localizedSeed: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }

    /// 書式キー（"%@..."）を現在の言語で解決し、引数を差し込む。
    /// 例: "%@を開始しますか?".localizedFormat(domain.workPhaseLabel)
    func localizedFormat(_ args: CVarArg...) -> String {
        String(format: localizedSeed, arguments: args)
    }
}
