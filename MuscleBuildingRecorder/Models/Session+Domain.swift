//
//  Session+Domain.swift
//  MuscleBuildingRecorder
//
//  Core Data の Session.domain (String?) を ActivityDomain に変換するアクセサ。
//  - 既存 v1 データ（domain == nil）は ActivityDomain.legacyDefault (= .workout) として扱う
//  - 不明な文字列値が入っていた場合も .workout にフォールバック
//

import Foundation
import CoreData

extension Session {
    /// 型安全な domain アクセサ。読み出し時は legacy フォールバック付き。
    var domainEnum: ActivityDomain {
        get { ActivityDomain(storedRawValue: domain) }
        set { domain = newValue.rawValue }
    }
}
