//
//  HistoryAggregator.swift
//  MuscleBuildingRecorder
//
//  履歴ダッシュボード用の集計ロジック（純 Swift + CoreData 参照のみ、SwiftUI 非依存）。
//  Session 群を「日付 × ドメイン」で集計し、カレンダーのドット表示・棒グラフ・
//  ドメイン別サマリに渡しやすい形へ変換する。
//

import Foundation
import CoreData

/// 1日分の活動集計（カレンダーのドット・サマリ用）
struct DayActivity: Identifiable {
    let day: Date                                   // calendar.startOfDay
    var domains: Set<ActivityDomain>                // その日に行ったドメイン（ドット表示）
    var workSecByDomain: [ActivityDomain: Int]      // ドメイン別の合計作業秒
    var sessionCountByDomain: [ActivityDomain: Int] // ドメイン別のセッション数

    var id: Date { day }
    var totalWorkSec: Int { workSecByDomain.values.reduce(0, +) }
}

/// ドメイン別の月間サマリ（サマリカード用）
struct DomainSummary: Identifiable {
    let domain: ActivityDomain
    let sessionCount: Int
    let totalWorkSec: Int

    var id: ActivityDomain { domain }
}

/// Swift Charts 用の1行（tuple は Chart に渡せないため名前付き struct）
struct ChartRow: Identifiable {
    let id = UUID()
    let day: Date
    let domain: ActivityDomain
    let workSec: Int
}

enum HistoryAggregator {

    /// 指定月（monthInterval）の範囲で、日付ごとの活動集計を作る。
    /// startedAt が nil のセッションは除外。
    static func dayActivities(
        from sessions: [Session],
        in monthInterval: DateInterval,
        calendar: Calendar
    ) -> [Date: DayActivity] {
        var result: [Date: DayActivity] = [:]

        for session in sessions {
            guard let started = session.startedAt, monthInterval.contains(started) else { continue }
            let day = calendar.startOfDay(for: started)
            let domain = session.domainEnum
            let workSec = Int(session.totalWorkSec)

            var entry = result[day] ?? DayActivity(
                day: day,
                domains: [],
                workSecByDomain: [:],
                sessionCountByDomain: [:]
            )
            entry.domains.insert(domain)
            entry.workSecByDomain[domain, default: 0] += workSec
            entry.sessionCountByDomain[domain, default: 0] += 1
            result[day] = entry
        }
        return result
    }

    /// 指定月のドメイン別サマリ（常に allCases 順で3件返す）。
    static func domainSummaries(
        from sessions: [Session],
        in monthInterval: DateInterval,
        calendar: Calendar
    ) -> [DomainSummary] {
        var counts: [ActivityDomain: Int] = [:]
        var secs: [ActivityDomain: Int] = [:]

        for session in sessions {
            guard let started = session.startedAt, monthInterval.contains(started) else { continue }
            let domain = session.domainEnum
            counts[domain, default: 0] += 1
            secs[domain, default: 0] += Int(session.totalWorkSec)
        }

        return ActivityDomain.allCases.map { domain in
            DomainSummary(
                domain: domain,
                sessionCount: counts[domain] ?? 0,
                totalWorkSec: secs[domain] ?? 0
            )
        }
    }

    /// 日別集計から棒グラフ用の行配列を作る（作業秒が 0 より大きい (日, ドメイン) のみ）。
    static func chartRows(from dayActivities: [Date: DayActivity]) -> [ChartRow] {
        var rows: [ChartRow] = []
        for (_, activity) in dayActivities {
            for domain in ActivityDomain.allCases {
                let sec = activity.workSecByDomain[domain] ?? 0
                if sec > 0 {
                    rows.append(ChartRow(day: activity.day, domain: domain, workSec: sec))
                }
            }
        }
        return rows.sorted { $0.day < $1.day }
    }
}
