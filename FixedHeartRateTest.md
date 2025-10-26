# 心拍数取得修正テストガイド

## 修正内容

1. **HKAnchoredObjectQueryを使用**
   - リアルタイム更新を受け取るように変更
   - 初回取得とリアルタイム更新の両方をサポート

2. **セッション開始タイミングを調整**
   - セッション開始後2秒待ってから心拍数モニタリング開始
   - ワークアウトセッションが安定してから取得

3. **エラーチェック強化**
   - クエリ実行時のエラーを詳細表示
   - 取得したサンプル数を表示

## テスト手順

### 1. 実機へデプロイ
```bash
1. Xcodeで実機 Apple Watch を接続
2. MuscleBuildingRecorderWatchTrue Watch App スキームを選択
3. 実機をターゲットに選択
4. Command + R で実行
```

### 2. デバッグ情報の確認

#### 起動直後
```
Debug Info
onAppear
Auth: 2          ← 権限OK
Mgr: Ready
Session: NotStarted
Query: None
Last HR: Never
```

#### 「開始」ボタンタップ後（メイン画面のまま）

##### 1. セッション開始（即座）
```
Mgr: Session started, init HR...
Session: Starting → Running
```

##### 2. 2秒後 - 心拍数モニタリング開始
```
Mgr: Now starting HR monitor... → Init anchored query → Query running
Query: Creating query... → Anchored active
```

##### 3. 初回データ取得（3-5秒後）
```
Query: Got [数値]  ← 取得したサンプル数
Mgr: Fresh または Old: Xs
Last HR: [X]s ago
心拍数: [実際の値] bpm
```

##### 4. リアルタイム更新（継続的）
```
Query: Live: [心拍数]
Last HR: 1s ago → 2s ago → 1s ago...
```

### 3. 期待される動作フロー

1. **セッション開始**
   - Session: `NotStarted` → `Starting` → `Running`

2. **2秒待機後**
   - Mgr: `Now starting HR monitor...`
   - Query: `Creating query...`

3. **Anchored Query実行**
   - Query: `Anchored active`
   - 初回結果: `Got [数値]`（取得したサンプル数）

4. **データ処理**
   - サンプルがある場合: `Live: [心拍数]`
   - サンプルがない場合: `Got 0`

### 4. トラブルシューティング

#### Query: "Got 0" が表示される場合

**原因**: HealthKitに心拍数データがない

**確認事項**:
1. Apple Watchが手首に装着されているか
2. 手首検出がオン（設定 → パスコード）
3. Apple Watchの心拍数アプリで値が表示されるか
4. ワークアウトを開始してから10-15秒待つ

**対処法**:
1. 心拍数表示エリアをタップして手動取得
2. 腕を動かして心拍センサーを活性化
3. Apple Watchの心拍数アプリを一度開いて閉じる

#### Query: "Error: init" または "Error: update"

**原因**: HealthKitクエリ実行エラー

**対処法**:
1. アプリを再起動
2. HealthKit権限を再確認
3. デバイスを再起動

#### Mgr: "Now starting HR monitor..." から変化しない

**原因**: startRealtimeHeartRateMonitoringが完了していない

**対処法**:
1. 5秒以上待つ
2. それでも変化しない場合はアプリ再起動

### 5. 成功判定

以下が確認できれば成功：

✅ Session が `Running` になる
✅ Query が `Anchored active` → `Got [数値]` → `Live: [心拍数]` と遷移
✅ 心拍数が0以外の値を表示
✅ Last HR が継続的に更新される
✅ Apple Watchの心拍数表示と近い値（±2-3 bpm）

### 6. バックアップ機能

Anchored Queryで取得できない場合、2秒ごとのタイマーがバックアップとして動作：
- fetchLatestHeartRate()が2秒ごとに実行
- 過去60秒のデータから最新を取得
- Query状態が更新される

## 注意事項

- ワークアウト開始直後は心拍数データがないため、10-15秒待つ必要がある
- 手首から外している場合はデータが取得できない
- 古いデータ（10秒以上前）の場合は`Old: Xs`と表示される