# リアルタイム心拍数モニタリング テストガイド

## 実装内容
Apple Watchの表示と同期する1秒間隔のリアルタイム心拍数取得を実装しました。

## テスト手順

### 1. 実機へのデプロイ
```bash
1. Xcodeで Apple Watch を接続
2. MuscleBuildingRecorderWatchTrue スキームを選択
3. 実機 Apple Watch をターゲットに選択
4. Command + R で実行
```

### 2. 起動時の確認

アプリ起動後、画面上部のデバッグ情報を確認：

```
Debug Info
Init
Auth: 2          ← 権限OK（2=許可済み）
Mgr: Ready
Session: NotStarted
Query: None
Last HR: Never
```

### 3. ワークアウト開始

「開始」ボタンをタップして、以下の状態変化を確認：

#### 正常な流れ:
```
Session: NotStarted → Created → Running
Query: None → Starting → Live: 72
Last HR: Never → 1s ago → 2s ago...
```

#### 実際の心拍数表示:
- メイン表示: **72 bpm** （実際の心拍数）
- Query欄: **Live: 72** （取得成功の証拠）
- Last HR: **1s ago** （更新頻度の確認）

### 4. リアルタイム更新の確認

1. **Apple Watchの心拍数アプリを開く**
   - ワークアウト中の心拍数を確認
   - 例: 75 bpm

2. **本アプリの表示を確認**
   - 1-2秒以内に同じ値に更新されるか
   - Last HRが「1s ago」「2s ago」と更新されるか

3. **運動強度を変える**
   - 腕を振る、歩くなどで心拍数を変化させる
   - Apple Watchの値と本アプリが同期して変化するか確認

### 5. 期待される動作

✅ **成功パターン:**
```
Session: Running
Query: Live: 82     ← リアルタイム値
Last HR: 1s ago     ← 最新更新
心拍数: 82 bpm      ← Apple Watchと一致
```

❌ **失敗パターン:**
```
Session: Running
Query: Error または Timeout
Last HR: 30s ago    ← 更新が止まっている
心拍数: 0 bpm       ← データ取得失敗
```

## トラブルシューティング

### Query: "Timeout" の場合
- 心拍センサーが正しく動作していない
- Apple Watchを手首にしっかり装着

### Query: "No data" の場合
- ワークアウトセッションが正しく開始されていない
- アプリを再起動して再試行

### Session: "Failed" の場合
- HealthKit権限を再確認
- デバイスを再起動

## 確認チェックリスト

- [ ] Session が "Running" になる
- [ ] Query が "Live: [数値]" を表示
- [ ] Last HR が "1s ago" や "2s ago" を表示
- [ ] 心拍数がApple Watchの表示と一致
- [ ] 1-2秒ごとに値が更新される
- [ ] 運動強度を変えると値が追従する

## 成功基準

以下が確認できれば、リアルタイム心拍数モニタリングは正常に動作しています：

1. **更新頻度**: Last HRが常に「5s ago」以内
2. **精度**: Apple Watch表示との差が±1-2 bpm以内
3. **安定性**: 5分以上継続して更新が続く

## ログの見方

デバッグ情報の各フィールド:
- **Auth**: HealthKit権限状態 (0=未決定, 1=拒否, 2=許可)
- **Session**: ワークアウトセッション状態
- **Query**: 心拍数クエリの状態とリアルタイム値
- **Last HR**: 最後の心拍数更新からの経過時間