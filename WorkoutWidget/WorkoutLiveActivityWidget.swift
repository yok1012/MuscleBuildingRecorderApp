//
//  WorkoutLiveActivityWidget.swift
//  WorkoutWidget
//
//  Dynamic Island / ロック画面 Live Activity の UI 構成。
//  ActivityAttributes 本体の定義は WorkoutAttributes.swift に切り出し済み。
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                            .foregroundColor(context.state.phase == "Work" ? .red : .blue)
                        Text(context.state.phase == "Work" ? "筋トレ" : "休憩")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 2) {
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
                    VStack(spacing: 2) {
                        liveTimer(context: context)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text("\(context.state.category) / \(context.state.exercise)")
                            .font(.caption2)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
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
                Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                    .font(.caption)
                    .foregroundColor(context.state.phase == "Work" ? .red : .blue)
            } compactTrailing: {
                liveTimer(context: context)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                    .font(.caption)
                    .foregroundColor(context.state.phase == "Work" ? .red : .blue)
            }
            .widgetURL(URL(string: "workoutapp://timer"))
            .keylineTint(context.state.phase == "Work" ? .red : .blue)
        }
    }

    /// フェーズ開始時刻が来ていれば OS ネイティブのライブタイマーを使い、秒単位で自動更新する。
    @ViewBuilder
    private func liveTimer(context: ActivityViewContext<WorkoutAttributes>) -> some View {
        if let start = context.state.phaseStartTime {
            Text(start, style: .timer)
        } else {
            Text(context.state.elapsedTime)
        }
    }
}

// MARK: - Lock Screen Live Activity View
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<WorkoutAttributes>

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: context.state.phase == "Work" ? "dumbbell.fill" : "pause.circle.fill")
                        .foregroundColor(context.state.phase == "Work" ? .red : .blue)
                    Text(context.state.phase == "Work" ? "筋トレ中" : "休憩中")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Text("\(context.state.category) / \(context.state.exercise)")
                    .font(.subheadline)
                    .opacity(0.85)
                    .lineLimit(1)
                if context.state.load > 0 {
                    Text("\(Int(context.state.load))kg × \(Int(context.state.reps))回")
                        .font(.caption)
                        .opacity(0.75)
                }
                Text("セット \(context.state.cycleIndex + 1)")
                    .font(.caption)
                    .opacity(0.6)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let start = context.state.phaseStartTime {
                    Text(start, style: .timer)
                        .font(.title)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text(context.state.elapsedTime)
                        .font(.title)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
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
        .activitySystemActionForegroundColor(.white)
        .activityBackgroundTint(context.state.phase == "Work" ? Color.red.opacity(0.25) : Color.blue.opacity(0.25))
    }
}
