//
//  ButtonLayoutConfig.swift
//  MuscleBuildingRecorder
//
//  メイン切替ボタン（休憩に移行 / 次のセットへ）の縦位置を設定する Pro 機能。
//  上部 / 中部 / 下部 の 3 択。
//

import Foundation
import Combine

/// メイン切替ボタンの縦位置
enum MainButtonVerticalPosition: String, Codable, CaseIterable, Identifiable {
    case top
    case middle
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "上部"
        case .middle: return "中部"
        case .bottom: return "下部"
        }
    }

    var icon: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .middle: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }
}

/// ボタン配置の永続化設定
struct ButtonLayoutConfig: Codable, Equatable {
    var mainButtonVerticalPosition: MainButtonVerticalPosition = .middle

    static let storageKey = "buttonLayoutConfig.v1"

    static func load() -> ButtonLayoutConfig {
        guard let data = AppGroupConfig.sharedUserDefaults?.data(forKey: storageKey) else {
            return ButtonLayoutConfig()
        }
        do {
            return try JSONDecoder().decode(ButtonLayoutConfig.self, from: data)
        } catch {
            print("ButtonLayoutConfig: decode failed: \(error)")
            return ButtonLayoutConfig()
        }
    }

    func save() {
        guard let defaults = AppGroupConfig.sharedUserDefaults else { return }
        do {
            let data = try JSONEncoder().encode(self)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            print("ButtonLayoutConfig: encode failed: \(error)")
        }
    }
}

/// View 側から購読するためのマネージャ
final class ButtonLayoutManager: ObservableObject {
    static let shared = ButtonLayoutManager()

    @Published var config: ButtonLayoutConfig {
        didSet { config.save() }
    }

    private init() {
        self.config = ButtonLayoutConfig.load()
    }

    func setMainButtonVerticalPosition(_ position: MainButtonVerticalPosition) {
        guard config.mainButtonVerticalPosition != position else { return }
        config.mainButtonVerticalPosition = position
    }
}
