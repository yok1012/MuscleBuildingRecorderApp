//
//  HistoryDashboardView.swift
//  MuscleBuildingRecorder
//
//  履歴タブの「ダッシュボード」モード。過去セッションを月単位で集計し、
//  カレンダー（日別ドメインドット）＋ 棒グラフ（日別×ドメイン）＋ ドメイン別サマリで可視化。
//

import SwiftUI
import Charts

struct HistoryDashboardView: View {
    let sessions: [Session]

    @State private var monthAnchor: Date = Date()
    private let calendar = Calendar.current

    // MARK: 派生集計（monthAnchor から計算）

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: monthAnchor)
            ?? DateInterval(start: monthAnchor, duration: 0)
    }

    private var dayMap: [Date: DayActivity] {
        HistoryAggregator.dayActivities(from: sessions, in: monthInterval, calendar: calendar)
    }

    private var summaries: [DomainSummary] {
        HistoryAggregator.domainSummaries(from: sessions, in: monthInterval, calendar: calendar)
    }

    private var chartRows: [ChartRow] {
        HistoryAggregator.chartRows(from: dayMap)
    }

    private var isEmptyMonth: Bool { dayMap.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthNavHeader

                MonthCalendarGrid(monthAnchor: monthAnchor, dayMap: dayMap, calendar: calendar)

                if isEmptyMonth {
                    emptyMonthView
                } else {
                    chartSection
                    summaryCards
                }
            }
            .padding()
        }
    }

    // MARK: 月ナビゲーション

    private var monthNavHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.title3)
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
        }
        .padding(.horizontal, 8)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: monthAnchor)
    }

    private func shiftMonth(_ delta: Int) {
        if let newDate = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            withAnimation(.easeInOut(duration: 0.2)) { monthAnchor = newDate }
        }
    }

    // MARK: グラフ

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日別アクティビティ（分）")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.secondary)
            Chart(chartRows) { row in
                BarMark(
                    x: .value("日", row.day, unit: .day),
                    y: .value("分", row.workSec / 60)
                )
                .foregroundStyle(by: .value("種別", row.domain.displayName))
            }
            .chartForegroundStyleScale([
                ActivityDomain.workout.displayName: Color.red,
                ActivityDomain.study.displayName: Color.blue,
                ActivityDomain.work.displayName: Color.green
            ])
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: サマリカード

    private var summaryCards: some View {
        HStack(spacing: 10) {
            ForEach(summaries) { summary in
                DomainSummaryCard(summary: summary)
            }
        }
    }

    private var emptyMonthView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("この月の記録はありません")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - 月カレンダー（日別ドメインドット）

private struct MonthCalendarGrid: View {
    let monthAnchor: Date
    let dayMap: [Date: DayActivity]
    let calendar: Calendar

    private var firstOfMonth: Date {
        let comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        return calendar.date(from: comps) ?? monthAnchor
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
    }

    /// 月初の前に入れる空白セル数（firstWeekday を尊重）
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// 曜日ヘッダ（firstWeekday から並べ替え）
    private var weekdaySymbols: [String] {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let start = calendar.firstWeekday - 1 // 0-based
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            // 曜日ヘッダ
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 44)
                }
                ForEach(1...daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) ?? firstOfMonth
        let activity = dayMap[calendar.startOfDay(for: date)]
        let isToday = calendar.isDateInToday(date)

        VStack(spacing: 3) {
            Text("\(day)")
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(activity == nil ? .secondary : .primary)
            HStack(spacing: 2) {
                if let activity = activity {
                    ForEach(ActivityDomain.allCases, id: \.self) { domain in
                        if activity.domains.contains(domain) {
                            Circle()
                                .fill(color(for: domain))
                                .frame(width: 6, height: 6)
                        }
                    }
                } else {
                    // 高さ揃えのためのプレースホルダ
                    Circle().fill(Color.clear).frame(width: 6, height: 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    private func color(for domain: ActivityDomain) -> Color {
        switch domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }
}

// MARK: - ドメイン別サマリカード

private struct DomainSummaryCard: View {
    let summary: DomainSummary

    private var accent: Color {
        switch summary.domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    private var minutes: Int { summary.totalWorkSec / 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: summary.domain.iconName)
                    .font(.caption)
                    .foregroundColor(accent)
                Text(summary.domain.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text("\(summary.sessionCount)")
                .font(.title3).fontWeight(.bold)
            + Text(" 回")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(minutes) 分")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(0.12))
        )
    }
}
