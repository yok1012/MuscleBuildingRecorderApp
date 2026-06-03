import SwiftUI
import CoreData

struct HistoryView: View {
    @EnvironmentObject var dataController: DataController
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Session.startedAt, ascending: false)],
        animation: .default
    ) var sessions: FetchedResults<Session>

    @State private var selectedSession: Session?
    @State private var searchText = ""
    /// nil = 全て表示、それ以外は単一ドメインに絞り込み
    @State private var domainFilter: ActivityDomain? = nil
    /// 表示モード: リスト / ダッシュボード
    @State private var mode: HistoryMode = .list

    private enum HistoryMode: String, CaseIterable {
        case list, dashboard
        var label: String { self == .list ? "リスト".localizedSeed : "ダッシュボード".localizedSeed }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(HistoryMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if mode == .list {
                    domainFilterBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                    List {
                        if filteredSessions.isEmpty {
                            EmptyHistoryView()
                        } else {
                            ForEach(filteredSessions) { session in
                                SessionHistoryRow(session: session)
                                    .onTapGesture {
                                        selectedSession = session
                                    }
                            }
                            .onDelete(perform: deleteSessions)
                        }
                    }
                    .searchable(text: $searchText, prompt: "日付・種目・タスクで検索")
                } else {
                    HistoryDashboardView(sessions: Array(sessions))
                }
            }
            .navigationTitle("履歴")
            .sheet(item: $selectedSession) { session in
                HistoryDetailView(session: session)
            }
        }
    }

    private var domainFilterBar: some View {
        HStack(spacing: 8) {
            filterChip(label: "全て".localizedSeed, icon: "list.bullet", isSelected: domainFilter == nil) {
                domainFilter = nil
            }
            ForEach(ActivityDomain.allCases, id: \.self) { domain in
                filterChip(
                    label: domain.displayName,
                    icon: domain.iconName,
                    isSelected: domainFilter == domain,
                    accent: chipColor(for: domain)
                ) {
                    domainFilter = (domainFilter == domain) ? nil : domain
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(
        label: String,
        icon: String,
        isSelected: Bool,
        accent: Color = .blue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? accent : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func chipColor(for domain: ActivityDomain) -> Color {
        switch domain {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    private var filteredSessions: [Session] {
        let domainMatched: [Session]
        if let filter = domainFilter {
            domainMatched = sessions.filter { $0.domainEnum == filter }
        } else {
            domainMatched = Array(sessions)
        }

        if searchText.isEmpty {
            return domainMatched
        }
        return domainMatched.filter { session in
            let dateString = session.startedAt?.formatted() ?? ""
            let title = session.title ?? ""
            let subjectOrProject = session.subjectOrProject ?? ""
            let records = (session.setRecords?.allObjects as? [SetRecord]) ?? []
            let exercises = records.compactMap { "\($0.category ?? "") \($0.name ?? "") \($0.taskName ?? "")" }.joined(separator: " ")
            return dateString.localizedCaseInsensitiveContains(searchText) ||
                   exercises.localizedCaseInsensitiveContains(searchText) ||
                   title.localizedCaseInsensitiveContains(searchText) ||
                   subjectOrProject.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = filteredSessions[index]
            dataController.container.viewContext.delete(session)
        }
        dataController.save()
    }
}

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("該当する履歴がありません")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("セッションを開始すると\nここに記録が表示されます")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SessionHistoryRow: View {
    let session: Session

    private var records: [SetRecord] {
        (session.setRecords?.allObjects as? [SetRecord] ?? [])
            .sorted { ($0.startAt ?? Date()) < ($1.startAt ?? Date()) }
    }

    private var dateString: String {
        guard let date = session.startedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private var durationString: String {
        let totalSeconds = Int(session.totalWorkSec + session.totalRestSec)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d分%d秒", minutes, seconds)
    }

    /// ドメイン別の主要ラベル（workout=種目カテゴリ、study/work=タスク名+科目/プロジェクト）
    private var primaryLabel: String {
        switch session.domainEnum {
        case .workout:
            let categories = Set(records.compactMap { $0.category })
            return categories.sorted().joined(separator: ", ")
        case .study, .work:
            let title = session.title ?? ""
            let secondary = session.subjectOrProject ?? ""
            if !title.isEmpty && !secondary.isEmpty {
                return "\(secondary) — \(title)"
            }
            return title.isEmpty ? secondary : title
        }
    }

    private var domainAccentColor: Color {
        switch session.domainEnum {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // ドメインバッジ
                Image(systemName: session.domainEnum.iconName)
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(domainAccentColor)
                    .clipShape(Circle())

                Text(dateString)
                    .font(.headline)
                Spacer()
                Text(durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(primaryLabel.isEmpty ? "(タイトルなし)".localizedSeed : primaryLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack {
                if session.domainEnum == .workout {
                    Label("\(records.filter { $0.phase == "Work" }.count)セット", systemImage: "dumbbell")
                        .font(.caption)
                    Spacer()
                    Label("Volume: \(Int(session.totalVolume))", systemImage: "sum")
                        .font(.caption)
                } else {
                    Label("\(records.filter { $0.phase == "Work" }.count)サイクル", systemImage: "repeat")
                        .font(.caption)
                    Spacer()
                    Label("集中: \(Int(session.totalWorkSec / 60))分", systemImage: "timer")
                        .font(.caption)
                }

                Spacer()

                if let avgHR = calculateAverageHR() {
                    Label("\(Int(avgHR)) bpm", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func calculateAverageHR() -> Double? {
        let heartRates = records.compactMap { $0.hrAvg }.filter { $0 > 0 }
        guard !heartRates.isEmpty else { return nil }
        return heartRates.reduce(0, +) / Double(heartRates.count)
    }
}