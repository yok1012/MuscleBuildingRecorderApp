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

    var body: some View {
        NavigationView {
            List {
                if sessions.isEmpty {
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
            .navigationTitle("ワークアウト履歴")
            .searchable(text: $searchText, prompt: "日付や種目で検索")
            .sheet(item: $selectedSession) { session in
                HistoryDetailView(session: session)
            }
        }
    }

    private var filteredSessions: [Session] {
        if searchText.isEmpty {
            return Array(sessions)
        } else {
            return sessions.filter { session in
                guard let records = session.setRecords?.allObjects as? [SetRecord] else { return false }
                let dateString = session.startedAt?.formatted() ?? ""
                let exercises = records.compactMap { "\($0.category ?? "") \($0.name ?? "")" }.joined(separator: " ")
                return dateString.localizedCaseInsensitiveContains(searchText) ||
                       exercises.localizedCaseInsensitiveContains(searchText)
            }
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
            Text("まだワークアウト履歴がありません")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("ワークアウトを開始すると\nここに記録が表示されます")
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

    private var mainExercises: String {
        let categories = Set(records.compactMap { $0.category })
        return categories.sorted().joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateString)
                    .font(.headline)
                Spacer()
                Text(durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(mainExercises)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack {
                Label("\(records.filter { $0.phase == "Work" }.count)セット", systemImage: "dumbbell")
                    .font(.caption)

                Spacer()

                Label("Volume: \(Int(session.totalVolume))", systemImage: "sum")
                    .font(.caption)

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