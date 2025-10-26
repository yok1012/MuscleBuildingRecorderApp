import ActivityKit
import WidgetKit
import SwiftUI

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
                        Text("Cycle \(context.state.cycleIndex + 1)")
                            .font(.caption2)
                            .opacity(0.7)
                        Spacer()
                        Text("タップで詳細")
                            .font(.caption2)
                            .opacity(0.5)
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

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
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

                    Text("Cycle \(context.state.cycleIndex + 1)")
                        .font(.caption)
                        .opacity(0.6)
                }

                Spacer()

                VStack(alignment: .trailing) {
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