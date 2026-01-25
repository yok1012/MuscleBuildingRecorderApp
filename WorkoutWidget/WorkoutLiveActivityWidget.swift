import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Workout Attributes (Live Activity用)
struct WorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String  // "Work" or "Rest"
        var elapsedTime: String
        var heartRate: Int
        var cycleIndex: Int
        var exercise: String
        var category: String
        var load: Double
        var reps: Double
    }

    var exerciseName: String
}

// MARK: - Live Activity Widget
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                            .foregroundColor(context.state.phase == "Work" ? .red : .blue)
                        Text(context.state.phase == "Work" ? "筋トレ" : "休憩")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("\(context.state.heartRate)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text("bpm")
                            .font(.system(size: 9))
                            .opacity(0.7)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.elapsedTime)
                            .font(.title2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Text("\(context.state.category) - \(context.state.exercise)")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // 重量と回数
                        if context.state.load > 0 {
                            Text("\(Int(context.state.load))kg × \(Int(context.state.reps))回")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                        Spacer()
                        Text("セット \(context.state.cycleIndex + 1)")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                }
            } compactLeading: {
                // Compact leading
                HStack {
                    Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                        .font(.caption)
                        .foregroundColor(context.state.phase == "Work" ? .red : .blue)
                    Text(context.state.elapsedTime)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            } compactTrailing: {
                // Compact trailing
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                    Text("\(context.state.heartRate)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            } minimal: {
                // Minimal
                Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                    .font(.caption)
                    .foregroundColor(context.state.phase == "Work" ? .red : .blue)
            }
            .widgetURL(URL(string: "workoutapp://timer"))
            .keylineTint(context.state.phase == "Work" ? .red : .blue)
        }
    }
}

// MARK: - Lock Screen Live Activity View
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                            .foregroundColor(context.state.phase == "Work" ? .red : .blue)
                        Text(context.state.phase == "Work" ? "筋トレ中" : "休憩中")
                            .font(.headline)
                            .fontWeight(.bold)
                    }

                    Text("\(context.state.category) - \(context.state.exercise)")
                        .font(.subheadline)
                        .opacity(0.8)

                    if context.state.load > 0 {
                        Text("\(Int(context.state.load))kg × \(Int(context.state.reps))回")
                            .font(.caption)
                            .opacity(0.7)
                    }

                    Text("セット \(context.state.cycleIndex + 1)")
                        .font(.caption)
                        .opacity(0.6)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(context.state.elapsedTime)
                        .font(.title)
                        .fontWeight(.semibold)
                        .monospacedDigit()

                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("\(context.state.heartRate) bpm")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
        }
        .activitySystemActionForegroundColor(.white)
        .activityBackgroundTint(context.state.phase == "Work" ? Color.red.opacity(0.3) : Color.blue.opacity(0.3))
    }
}
