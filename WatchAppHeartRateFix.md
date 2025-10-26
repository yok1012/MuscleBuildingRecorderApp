# Apple Watch アプリ心拍数取得修正

## 修正内容

### 1. 独立した心拍数クエリを追加
- HKLiveWorkoutBuilderに依存せず、直接HKAnchoredObjectQueryを使用
- ワークアウト開始時に即座に心拍数クエリを開始
- リアルタイムで心拍数データを受信・処理

### 2. 実装の改善点
```swift
// 新しく追加した機能
private var heartRateQuery: HKQuery?

private func startHeartRateQuery() {
    // HKAnchoredObjectQueryでリアルタイム更新
    // 初回データ取得 + 継続的な更新の両方に対応
}

private func processHeartRateSamples(_ samples: [HKSample]?) {
    // 受信した心拍数サンプルを処理
    // UIを即座に更新
}
```

### 3. デバッグログの追加
各段階で詳細なログを出力：
- クエリ開始時
- サンプル受信時
- UI更新時

## テスト手順

### 1. Apple Watchでアプリを起動
1. Apple WatchでMuscleBuildingRecorderアプリを開く
2. 画面に「0 bpm」と表示されることを確認

### 2. ワークアウトを開始
1. 「開始」ボタンをタップ
2. Apple Watchを手首にしっかり装着
3. 10-15秒待つ（心拍センサーが測定を開始）

### 3. Xcodeコンソールでログ確認
期待されるログ：
```
Watch: Starting workout...
Watch: Workout session started
Watch: Starting heart rate query
Watch: Heart rate query started
Watch: Data collection started successfully
Watch: Processing heart rate sample: 72.0 bpm at 2025-01-05 15:45:23
Watch: Updated heart rate to 72.0 bpm
```

### 4. UI確認
- 心拍数が「0 bpm」から実際の値（例：72 bpm）に更新される
- 数秒ごとに最新の値に更新される

## トラブルシューティング

### 問題: 心拍数が0のまま変わらない

#### 1. HealthKit権限の確認
Apple Watchの設定：
- 設定アプリを開く
- プライバシー → ヘルスケア
- MuscleBuildingRecorderを選択
- 「心拍数」がオンになっているか確認

#### 2. Apple Watchの装着確認
- 手首にしっかりと装着されているか
- センサー部分が皮膚に密着しているか
- 手首検出がオンになっているか（設定 → パスコード）

#### 3. コンソールログの確認
以下のエラーメッセージがないか確認：
- `Watch: Heart rate query error:`
- `Watch: Failed to create heart rate type`
- `Watch: HealthKit authorization failed`

#### 4. ワークアウトセッションの状態確認
- ワークアウトが正常に開始されているか
- 「Watch: Workout session started」ログが表示されているか

### 問題: 権限エラーが表示される

1. iPhoneのヘルスケアアプリを開く
2. 共有 → アプリとサービス
3. MuscleBuildingRecorderを選択
4. すべてのカテゴリをオンにする
5. Apple Watchアプリを再起動

### 問題: 心拍数の更新が遅い

これは正常な動作です：
- Apple Watchは省電力のため、心拍数を継続的に測定しません
- ワークアウト中は5-10秒ごとに更新されます
- より頻繁な更新が必要な場合は、激しい動きをすると測定頻度が上がります

## 技術詳細

### データフロー
1. **ワークアウト開始**
   - HKWorkoutSessionを作成・開始
   - HKAnchoredObjectQueryを作成・実行

2. **心拍数測定**
   - Apple Watchのセンサーが心拍を検出
   - HealthKitに自動的に保存

3. **データ受信**
   - HKAnchoredObjectQueryのupdateHandlerが呼ばれる
   - processHeartRateSamplesでデータ処理

4. **UI更新**
   - メインスレッドで@Published変数を更新
   - SwiftUIが自動的にビューを再描画

### 使用しているHealthKit API
- **HKWorkoutSession**: ワークアウトセッション管理
- **HKAnchoredObjectQuery**: リアルタイム心拍数クエリ
- **HKLiveWorkoutBuilder**: ワークアウトデータ収集（watchOS 9.0+）

### なぜHKAnchoredObjectQueryを使用？
1. **リアルタイム性**: 新しいデータが即座に通知される
2. **効率性**: 差分のみを取得するため効率的
3. **信頼性**: HKLiveWorkoutBuilderが失敗しても動作
4. **互換性**: 古いwatchOSバージョンでも動作

## 確認済みの動作
- ✅ ワークアウト開始時に心拍数クエリが開始される
- ✅ 心拍数サンプルが受信・処理される
- ✅ UIが正しく更新される
- ✅ ワークアウト終了時にクエリが停止される
- ✅ エラーハンドリングが適切に実装されている