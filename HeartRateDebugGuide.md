# 心拍数取得デバッグガイド

## 修正内容

1. **即座にタイマー開始**: セッション開始直後にリアルタイム監視を開始
2. **デバッグ情報強化**: 各ステップでの状態をUI上に表示
3. **取得範囲拡大**: 過去60秒までのデータを検索

## デバッグ情報の見方

### Mgr欄の表示パターン

#### タイマー初期化時
- `Creating timer` → タイマー作成中
- `First fetch` → 初回取得実行
- `HR monitor active` → 監視開始完了

#### データ取得時
- `Fresh data` → 10秒以内の新しいデータ取得成功
- `Old: Xs` → X秒前の古いデータ（10秒以上）
- `Empty result` → データなし
- `Query err` → クエリエラー

### Query欄の表示パターン

#### 正常系
- `Init timer...` → タイマー初期化中
- `Timer ready` → タイマー準備完了
- `Live: 72` → リアルタイム心拍数（72 bpm）

#### 異常系
- `No HR type` → HealthKitタイプ作成失敗
- `No type` → fetchでタイプなし
- `Error` → クエリ実行エラー
- `No data` → サンプルなし

### Last HR欄
- `Never` → まだ取得していない
- `Xs ago` → X秒前のデータ
- `No samples` → サンプルなし

## テスト手順

### 1. アプリ起動直後

```
Debug Info
Init
Auth: 2          ← 権限OK
Mgr: Ready
Session: NotStarted
Query: None
Last HR: Never
```

### 2. 「開始」ボタンタップ直後

```
Mgr: Starting HR monitor...
Session: Starting
Query: Init timer...
```

### 3. タイマー開始後（1秒以内）

```
Mgr: First fetch または Fresh data
Session: Running
Query: Timer ready → Live: [心拍数]
Last HR: [X]s ago
```

## トラブルシューティング

### Query: "None" のまま変化しない

**原因**: タイマーが開始されていない

**確認事項**:
1. Mgrに「Creating timer」が表示されるか
2. Sessionが「Running」になっているか

**対処法**:
- アプリを再起動
- ワークアウトを停止して再開始

### Query: "No data" が続く

**原因**: HealthKitにデータがない

**確認事項**:
1. Apple Watchを正しく装着しているか
2. 手首検出がオンか
3. Apple Watchの心拍数アプリで値が表示されるか

**対処法**:
1. Apple Watchの心拍数アプリを開く
2. 心拍数が表示されることを確認
3. 本アプリでワークアウトを開始
4. 心拍数エリアをタップして手動取得

### Query: "Error" が表示される

**原因**: HealthKitクエリ実行エラー

**対処法**:
1. 権限を再確認（Auth: 2であること）
2. デバイスを再起動
3. HealthKitの設定を確認

## 期待される動作フロー

1. **開始ボタンタップ**
   - Mgr: `Starting HR monitor...`
   - Query: `Init timer...`

2. **タイマー作成完了**（即座）
   - Mgr: `Creating timer`
   - Query: `Timer ready`

3. **初回取得実行**（即座）
   - Mgr: `First fetch`

4. **データ取得成功**（1-2秒後）
   - Mgr: `Fresh data`
   - Query: `Live: 72`
   - Last HR: `1s ago`

5. **継続的な更新**（1秒ごと）
   - Query: `Live: [最新値]`
   - Last HR: `1s ago` → `2s ago` → `1s ago`（繰り返し）

## 成功判定

以下が確認できれば正常動作：

✅ Query欄に「Live: [数値]」が表示される
✅ Last HR欄が「5s ago」以内で更新される
✅ 心拍数がApple Watchの表示と近い値
✅ 1-2秒ごとに値が更新される