# 心拍数モニタリング修正完了

## 実装した修正内容

### 1. iOS用のクエリ方式を改善
- **HKAnchoredObjectQuery** から **HKSampleQuery + HKObserverQuery** に変更
- 最新の心拍数サンプルを取得し、新しいデータが利用可能になったら自動更新
- 古いサンプル（5分以上前）は自動的に除外

### 2. 認証状態の詳細ログ追加
```
HealthKit: Heart rate authorization status: 2
(0=notDetermined, 1=sharingDenied, 2=sharingAuthorized)
```

### 3. UIにステータス表示を追加
- 接続状態を視覚的に表示（緑●=データ受信中、黄●=接続済み待機中、赤●=未接続）
- ステータスメッセージで現在の状態を日本語表示

### 4. デバッグ用テストモード追加（DEBUG ビルドのみ）
- 実際の心拍計がない場合、3秒後に自動的にシミュレーションデータを生成
- リアルなデータ変動をシミュレート（60-180 bpm範囲）

## テスト手順

### ステップ 1: アプリを起動
1. Xcodeでアプリを実行
2. iOSシミュレータまたは実デバイスで起動

### ステップ 2: コンソールログを確認
Xcodeのコンソールで以下のログを確認：

**正常な接続フロー:**
```
HeartRateManager: Connecting to healthKit...
HealthKit: Starting connection...
HealthKit: Heart rate authorization status: 2 (sharingAuthorized)
HealthKit: Authorization granted
HealthKit iOS: Starting heart rate monitoring
HealthKit iOS: Observer query started
HealthKit: Heart rate query started
HeartRateManager: Successfully connected to healthKit
```

**テストモード（実データなしの場合）:**
```
HealthKit: No real heart rate data detected, starting simulation for testing
HealthKit TEST: Simulating heart rate: 72.5 bpm
HeartRateManager: Received heart rate: 72.5 bpm
```

### ステップ 3: UI確認
メインタイマー画面で以下を確認：
1. 心拍数表示エリアの下にステータスインジケーターが表示される
2. 以下の状態を確認：
   - 🔴 未接続
   - 🟡 healthKit接続済み - データ待機中
   - 🟢 healthKit接続済み（データ受信中）

### ステップ 4: 実デバイステスト（Apple Watch必要）

#### Apple Watchで心拍数を測定する場合：
1. Apple WatchとiPhoneがペアリング済みであることを確認
2. 設定 → プライバシーとセキュリティ → ヘルスケア → MuscleBuildingRecorder で「心拍数」の読み取りを許可
3. Apple Watchでワークアウトアプリを起動（筋力トレーニングを選択）
4. MuscleBuildingRecorderアプリを起動
5. 心拍数データが表示されることを確認

#### Apple Watchアプリを使用する場合：
1. Apple Watchでアプリを起動
2. 「開始」をタップ
3. 心拍数が表示されることを確認

## トラブルシューティング

### 問題: 「sharingDenied」と表示される
**解決方法:**
1. iPhoneの設定 → プライバシーとセキュリティ → ヘルスケア
2. MuscleBuildingRecorderを選択
3. 「心拍数」をオンにする

### 問題: データが表示されない（実デバイス）
**確認事項:**
1. Apple Watchを着用しているか
2. Apple Watchでワークアウトが開始されているか
3. 最近（5分以内）の心拍数データがあるか

### 問題: シミュレータでデータが表示されない
**確認事項:**
1. DEBUGビルドであることを確認（Scheme → Run → Build Configuration → Debug）
2. 3秒待つ（自動シミュレーション開始）
3. コンソールで「TEST: Simulating heart rate」メッセージを確認

## 技術詳細

### iOS プラットフォーム
- **HKSampleQuery**: 最新の心拍数サンプルを1件取得
- **HKObserverQuery**: 新しいデータが利用可能になったら通知を受信
- 5分以内のデータのみを使用（古いデータは無視）

### watchOS プラットフォーム
- **HKAnchoredObjectQuery**: リアルタイムの心拍数更新を受信
- **HKWorkoutSession**: ワークアウト中の継続的なデータ収集

### データフロー
1. HealthKit認証リクエスト
2. 権限確認（status = 2 で許可）
3. クエリ開始（iOS: SampleQuery + ObserverQuery）
4. データ受信時に HeartRateSubject に送信
5. HeartRateManager が受信してUIを更新
6. MainTimerView で表示

## 今後の改善案

1. **Bluetooth心拍計サポート**: 外部デバイスとの接続
2. **AirPods Pro対応**: 心拍センサー搭載モデルのサポート
3. **履歴グラフ**: セッション中の心拍数変動をグラフ表示
4. **心拍ゾーン計算**: 年齢に基づく目標心拍ゾーンの表示