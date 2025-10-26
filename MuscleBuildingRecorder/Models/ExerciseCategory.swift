import Foundation

// エクササイズカテゴリーの定義
enum ExerciseCategory: String, CaseIterable, Identifiable {
    case chest = "胸"
    case back = "背中"
    case legs = "脚"
    case shoulders = "肩"
    case arms = "腕"
    case core = "体幹"
    case cardio = "有酸素"
    case other = "その他"

    var id: String { self.rawValue }

    var displayName: String {
        return self.rawValue
    }

    var icon: String {
        switch self {
        case .chest:
            return "figure.strengthtraining.traditional"
        case .back:
            return "figure.strengthtraining.functional"
        case .legs:
            return "figure.walk"
        case .shoulders:
            return "figure.cooldown"
        case .arms:
            return "figure.arms.open"
        case .core:
            return "figure.core.training"
        case .cardio:
            return "figure.run"
        case .other:
            return "questionmark.circle"
        }
    }

    var sortOrder: Int {
        switch self {
        case .chest: return 1
        case .back: return 2
        case .legs: return 3
        case .shoulders: return 4
        case .arms: return 5
        case .core: return 6
        case .cardio: return 7
        case .other: return 8
        }
    }

    // 既存のカテゴリー文字列から Enum に変換
    static func from(string: String) -> ExerciseCategory {
        switch string {
        case "胸": return .chest
        case "背中": return .back
        case "脚": return .legs
        case "肩": return .shoulders
        case "腕": return .arms
        case "体幹": return .core
        case "有酸素": return .cardio
        default: return .other
        }
    }
}