import WidgetKit
import SwiftUI

// MARK: - Timeline Provider
struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: Date(), state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        let state = WidgetStateStore.loadStateFromAppGroup()
        let entry = WorkoutEntry(date: Date(), state: state)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let state = WidgetStateStore.loadStateFromAppGroup()
        let entry = WorkoutEntry(date: Date(), state: state)

        // 次の更新は30秒後
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry
struct WorkoutEntry: TimelineEntry {
    let date: Date
    let state: WorkoutStateSnapshot
}

// MARK: - Widget View
struct WorkoutWidgetEntryView: View {
    var entry: WorkoutTimelineProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidgetView
        case .systemMedium:
            mediumWidgetView
        case .systemLarge:
            largeWidgetView
        case .accessoryCircular:
            accessoryCircularView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryInline:
            accessoryInlineView
        default:
            smallWidgetView
        }
    }

    // MARK: - Small Widget
    private var smallWidgetView: some View {
        VStack(spacing: 8) {
            // Phase indicator
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 12, height: 12)
                Text(entry.state.phaseDisplayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Timer
            Text(entry.state.elapsedTimeString)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.7)

            // Heart rate
            if entry.state.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("\(entry.state.heartRate) bpm")
                        .font(.caption)
                }
            }

            Spacer()

            // Exercise name
            if !entry.state.exercise.isEmpty {
                Text(entry.state.exercise)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            phaseGradient
        }
    }

    // MARK: - Medium Widget
    private var mediumWidgetView: some View {
        HStack(spacing: 16) {
            // Left: Timer and Phase
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 14, height: 14)
                    Text(entry.state.phaseDisplayName)
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Text(entry.state.elapsedTimeString)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.7)

                if entry.state.phase == "rest", let remaining = entry.state.restRemainingTime {
                    Text("残り \(formatTime(remaining))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Right: Stats
            VStack(alignment: .leading, spacing: 8) {
                // Heart rate
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("\(entry.state.heartRate) bpm")
                        .font(.headline)
                }

                // Exercise
                if !entry.state.exercise.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundColor(.orange)
                        Text(entry.state.exercise)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }

                // Load and Reps
                if entry.state.load > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(.blue)
                        Text("\(Int(entry.state.load))kg × \(Int(entry.state.reps))回")
                            .font(.subheadline)
                    }
                }

                // Cycle
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .foregroundColor(.green)
                    Text("セット \(entry.state.cycleIndex + 1)")
                        .font(.caption)
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(for: .widget) {
            phaseGradient
        }
    }

    // MARK: - Large Widget
    private var largeWidgetView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 16, height: 16)
                Text(entry.state.phaseDisplayName)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text("セット \(entry.state.cycleIndex + 1)")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Timer
            Text(entry.state.elapsedTimeString)
                .font(.system(size: 56, weight: .bold, design: .monospaced))

            if entry.state.phase == "rest", let remaining = entry.state.restRemainingTime {
                Text("残り \(formatTime(remaining))")
                    .font(.headline)
                    .foregroundColor(.orange)
            }

            Divider()

            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCell(icon: "heart.fill", color: .red, title: "心拍数", value: "\(entry.state.heartRate) bpm")
                statCell(icon: "dumbbell.fill", color: .orange, title: "種目", value: entry.state.exercise)
                statCell(icon: "scalemass.fill", color: .blue, title: "重量", value: "\(Int(entry.state.load))kg")
                statCell(icon: "number", color: .green, title: "回数", value: "\(Int(entry.state.reps))回")
            }

            Divider()

            // Totals
            HStack {
                VStack {
                    Text("ワーク時間")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTime(entry.state.totalWorkTime))
                        .font(.headline)
                        .foregroundColor(.red)
                }
                Spacer()
                VStack {
                    Text("休憩時間")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatTime(entry.state.totalRestTime))
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            phaseGradient
        }
    }

    // MARK: - Accessory Views (Lock Screen)
    private var accessoryCircularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: entry.state.phase == "work" ? "flame.fill" : "bed.double.fill")
                    .font(.title3)
                Text(entry.state.elapsedTimeString)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: entry.state.phase == "work" ? "flame.fill" : "bed.double.fill")
                Text(entry.state.phaseDisplayName)
                    .fontWeight(.semibold)
            }
            Text(entry.state.elapsedTimeString)
                .font(.title2)
                .fontWeight(.bold)
            if entry.state.heartRate > 0 {
                Text("\(entry.state.heartRate) bpm")
                    .font(.caption)
            }
        }
    }

    private var accessoryInlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.state.phase == "work" ? "flame.fill" : "bed.double.fill")
            Text("\(entry.state.phaseDisplayName) \(entry.state.elapsedTimeString)")
        }
    }

    // MARK: - Helper Views
    private func statCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Helper Properties
    private var phaseColor: Color {
        switch entry.state.phase {
        case "work": return .red
        case "rest": return .blue
        default: return .gray
        }
    }

    private var phaseGradient: some View {
        LinearGradient(
            colors: [
                phaseColor.opacity(0.3),
                phaseColor.opacity(0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Widget Configuration
struct WorkoutWidget: Widget {
    let kind: String = "WorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            WorkoutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("ワークアウト")
        .description("トレーニングの進捗状況を表示します")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    WorkoutWidget()
} timeline: {
    WorkoutEntry(date: Date(), state: .empty)
    WorkoutEntry(date: Date(), state: WorkoutStateSnapshot(
        phase: "work",
        phaseDisplayName: "ワーク",
        elapsedTimeString: "01:23",
        totalWorkTime: 300,
        totalRestTime: 120,
        currentPhaseTime: 83,
        heartRate: 145,
        cycleIndex: 2,
        exercise: "ベンチプレス",
        category: "胸",
        load: 60,
        reps: 10,
        timestamp: Date(),
        restRemainingTime: nil,
        targetRestTime: nil
    ))
}
