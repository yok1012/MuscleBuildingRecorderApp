import Foundation

enum WorkoutPhase: String, CaseIterable {
    case idle = "Idle"
    case work = "Work"
    case rest = "Rest"

    var displayName: String {
        switch self {
        case .idle: return "待機中"
        case .work: return "筋トレ"
        case .rest: return "休憩"
        }
    }

    var color: String {
        switch self {
        case .idle: return "gray"
        case .work: return "red"
        case .rest: return "blue"
        }
    }
}