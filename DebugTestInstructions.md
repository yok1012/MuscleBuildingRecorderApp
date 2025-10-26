# デバッグテスト手順

## 変更内容
ワークアウト開始時のシート表示を無効化し、メイン画面でデバッグ情報を確認できるようにしました。

## テスト手順

### 1. 実機へデプロイ
```bash
1. Xcodeで Apple Watch を接続
2. MuscleBuildingRecorderWatchTrue Watch App スキームを選択
3. 実機をターゲットに選択
4. Command + R で実行
```

### 2. メイン画面でのデバッグ確認

#### 起動直後
```
Debug Info
onAppear
Auth: 2
Mgr: Ready
Session: NotStarted
Query: None
Last HR: Never
```

#### 「開始」ボタンタップ後（シートは表示されません）

メイン画面のまま、以下の変化を確認：

```
Debug Info
Starting...
Auth: 2
Mgr: Starting HR monitor... → Creating timer → First fetch
Session: NotStarted → Starting → Running
Query: None → Init timer... → Timer ready → Live: [心拍数]
Last HR: Never → [X]s ago
---（ワークアウト中のみ表示）---
Active: YES
Timer: 00:00:03
```

### 3. 確認ポイント

#### ✅ Session状態の遷移
1. `NotStarted` - 初期状態
2. `Starting` - セッション開始中
3. `Running` - 実行中（この状態でないと心拍数取得不可）

#### ✅ Query状態の遷移
1. `None` - 初期状態
2. `Init timer...` - タイマー初期化中
3. `Timer ready` - タイマー準備完了
4. `Live: 72` - リアルタイム心拍数取得成功
5. `No data` - データなし（エラーではない）
6. `Error` - クエリエラー

#### ✅ Mgr（Manager）メッセージ
1. `Starting HR monitor...` - 監視開始処理中
2. `Creating timer` - タイマー作成中
3. `First fetch` - 初回取得実行
4. `HR monitor active` - 監視アクティブ
5. `Fresh data` - 新しいデータ取得（10秒以内）
6. `Old: 15s` - 古いデータ（15秒前）
7. `Empty result` - 結果なし

### 4. トラブルシューティング

#### Query が "None" のまま
- **原因**: タイマーが開始されていない
- **確認**: Mgrに「Creating timer」が表示されるか
- **対処**: アプリ再起動

#### Query が "No data"
- **原因**: 心拍数データがない
- **確認**:
  1. Apple Watchが手首に装着されているか
  2. 手首検出がオン（設定 → パスコード）
  3. Apple Watchの心拍数アプリで値が表示されるか

#### Session が "Running" にならない
- **原因**: ワークアウトセッション開始失敗
- **対処**:
  1. HealthKit権限確認（Auth: 2であること）
  2. デバイス再起動

### 5. 期待される結果

正常動作時の流れ：

1. **開始ボタンタップ**
   - Mgr: `Starting HR monitor...`
   - Session: `Starting`

2. **1秒以内**
   - Mgr: `Creating timer` → `First fetch`
   - Session: `Running`
   - Query: `Timer ready`

3. **2-3秒後**
   - Query: `Live: 72`（実際の心拍数）
   - Last HR: `1s ago`
   - Active: `YES`

4. **継続的な更新**
   - 心拍数が1-2秒ごとに更新
   - Last HRが常に5秒以内

### 6. 手動心拍数取得

心拍数表示エリア（ハートアイコン）をタップすると手動取得：
- 成功: 実際の心拍数表示
- エラー: 99表示
- データなし: 88表示

## 成功判定基準

✅ Session が "Running" になる
✅ Query が "Live: [数値]" を表示
✅ 心拍数が0以外の値を表示
✅ Last HR が更新される
✅ Timer がカウントアップする