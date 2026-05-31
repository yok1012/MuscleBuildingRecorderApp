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

// MARK: - Domain helpers (Widget 側にローカルに定義。本体の ActivityDomain と意味は同じ)
private enum LiveActivityDomain: String {
    case workout, study, work

    init(rawString: String?) {
        switch rawString {
        case "study": self = .study
        case "work":  self = .work
        default:      self = .workout  // nil・不明値は workout（後方互換）
        }
    }

    /// 作業中のアイコン（domain と phase の組み合わせで決まる）
    var workIcon: String {
        switch self {
        case .workout: return "dumbbell.fill"
        case .study:   return "book.fill"
        case .work:    return "briefcase.fill"
        }
    }

    /// 作業中のアクセントカラー
    var accentColor: Color {
        switch self {
        case .workout: return .red
        case .study:   return .blue
        case .work:    return .green
        }
    }

    /// Work フェーズ中のラベル
    var workPhaseLabel: String {
        switch self {
        case .workout: return "筋トレ"
        case .study:   return "勉強"
        case .work:    return "作業"
        }
    }
}

private func domainIcon(for state: WorkoutAttributes.ContentState) -> String {
    let domain = LiveActivityDomain(rawString: state.domain)
    return state.phase == "Work" ? domain.workIcon : "pause.circle.fill"
}

private func domainPhaseColor(for state: WorkoutAttributes.ContentState) -> Color {
    let domain = LiveActivityDomain(rawString: state.domain)
    return state.phase == "Work" ? domain.accentColor : .blue
}

private func domainPhaseLabel(for state: WorkoutAttributes.ContentState) -> String {
    let domain = LiveActivityDomain(rawString: state.domain)
    return state.phase == "Work" ? domain.workPhaseLabel : "休憩"
}

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
                        Image(systemName: domainIcon(for: context.state))
                            .foregroundColor(domainPhaseColor(for: context.state))
                        Text(domainPhaseLabel(for: context.state))
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
                Image(systemName: domainIcon(for: context.state))
                    .font(.caption)
                    .foregroundColor(domainPhaseColor(for: context.state))
            } compactTrailing: {
                liveTimer(context: context)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: domainIcon(for: context.state))
                    .font(.caption)
                    .foregroundColor(domainPhaseColor(for: context.state))
            }
            .widgetURL(URL(string: "workoutapp://timer"))
            .keylineTint(domainPhaseColor(for: context.state))
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

    private var isWorkout: Bool {
        LiveActivityDomain(rawString: context.state.domain) == .workout
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: domainIcon(for: context.state))
                        .foregroundColor(domainPhaseColor(for: context.state))
                    Text(domainPhaseLabel(for: context.state) + "中")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                // workout: カテゴリ/種目、study/work: 種目欄をタスク名として表示
                Text(isWorkout
                     ? "\(context.state.category) / \(context.state.exercise)"
                     : (context.state.exercise.isEmpty ? "(タスク未設定)" : context.state.exercise))
                    .font(.subheadline)
                    .opacity(0.85)
                    .lineLimit(1)
                // load×reps は workout のみ表示
                if isWorkout, context.state.load > 0 {
                    Text("\(Int(context.state.load))kg × \(Int(context.state.reps))回")
                        .font(.caption)
                        .opacity(0.75)
                }
                Text(isWorkout ? "セット \(context.state.cycleIndex + 1)" : "サイクル \(context.state.cycleIndex + 1)")
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
        .activityBackgroundTint(domainPhaseColor(for: context.state).opacity(0.25))
    }
}
