import Foundation
import CoreData

/// SetRecord.note フィールドに JSON 形式で格納する構造化ペイロード。
/// - 既存仕様との後方互換: note が JSON でなければ memo として読み出される
/// - 拡張用フィールド:
///   - rpe（肉体的疲労度 1-5、F-2 で 10 段階から 5 段階に変更し意味も明確化）
///   - mentalRpe（精神的疲労度 1-5、F-2 で追加）
///   - nextAction（"up" / "down" / "keep"）
struct SetRecordPayload: Codable, Equatable {
    var tags: [String] = []
    var memo: String = ""
    /// 肉体的疲労度（Physical RPE）1-5。nil なら未入力
    var rpe: Int? = nil
    /// 精神的疲労度（Mental RPE）1-5。nil なら未入力（F-2 で追加）
    var mentalRpe: Int? = nil
    /// 次回アクション "up" / "down" / "keep"。nil なら未入力
    var nextAction: String? = nil

    /// note 文字列からデコード。JSON でなければ memo として扱う。
    static func decode(from rawNote: String?) -> SetRecordPayload {
        guard let raw = rawNote, !raw.isEmpty else { return SetRecordPayload() }
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SetRecordPayload.self, from: data) {
            return decoded
        }
        return SetRecordPayload(memo: raw)
    }

    /// JSON 文字列にエンコード。失敗時は memo を平文で返す。
    func encodeToNote() -> String? {
        if tags.isEmpty && rpe == nil && mentalRpe == nil && nextAction == nil {
            // 平文 memo として保存（後方互換）
            return memo.isEmpty ? nil : memo
        }
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    var isEmpty: Bool {
        tags.isEmpty && memo.isEmpty && rpe == nil && mentalRpe == nil && nextAction == nil
    }
}

extension SetRecord {
    /// note フィールドに格納された構造化ペイロード
    var payload: SetRecordPayload {
        get { SetRecordPayload.decode(from: note) }
        set { note = newValue.encodeToNote() }
    }
}
