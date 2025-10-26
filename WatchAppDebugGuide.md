# Apple Watch 実機デバッグガイド

## 修正内容の概要

Apple Watch実機で心拍数が0のまま表示される問題を解決するため、以下の修正を実装しました：

### 1. 包括的なデバッグログの追加
- 各処理段階で詳細なログを出力
- エラー箇所を特定しやすくするため、ERROR/WARNINGレベルを明記

### 2. 複数の心拍数取得方式を実装
- **HKSampleQuery**: 既存の心拍数データを取得
- **HKAnchoredObjectQuery**: リアルタイム更新を受信
- **HKObserverQuery**: バックアップとして変更を監視

### 3. ワークアウトセッション管理の強化
- `healthStore.start(session)`の呼び出しを追加
- セッション状態変化の詳細ログ
- HKLiveWorkoutBuilder初期化の確認

## 実機でのテスト手順

### 1. Xcodeでの準備
1. Apple WatchとiPhoneを接続
2. Xcodeで「MuscleBuildingRecorder」スキームを選択
3. 実機のApple Watchをターゲットに選択
4. Command + Shift + K でクリーンビルド
5. Command + R で実行

### 2. コンソールログの確認
Xcodeのコンソールで以下のログメッセージを確認してください：

#### 正常なフロー
```
Watch: Starting workout...
Watch: Current platform: watchOS
Watch: Creating workout session...
Watch: Workout session created
Watch: Starting workout session activity...
Watch: Called healthStore.start(session)
Watch: Workout session activity started
Watch: About to start heart rate query...
Watch: Current heart rate authorization: 2
Watch: Sample query found 5 recent samples
Watch:   Sample: 72.0 bpm at 2025-01-05 16:30:00
Watch: Processing 5 heart rate samples
Watch: Updating UI with heart rate: 72.0 bpm
```

#### エラーパターン
```
Watch ERROR: Health data not available!
Watch ERROR: Failed to create heart rate type
Watch ERROR: Sample query failed: [エラー詳細]
Watch WARNING: Heart rate not authorized. Status: 1
```

### 3. チェックポイント

#### A. 権限確認
コンソールで以下を確認：
- `Watch: Heart rate auth status: 2` （2=許可済み）
- 1の場合は権限拒否、0の場合は未決定

**対処法**：
1. Apple Watchの設定アプリを開く
2. プライバシーとセキュリティ → ヘルスケア
3. MuscleBuildingRecorderを選択
4. 「心拍数」をオン

#### B. ワークアウトセッション状態
コンソールで以下を確認：
- `Watch: State names: NotStarted -> Running`
- `Watch: Session is now RUNNING`

**問題がある場合**：
- `Watch ERROR: Workout session failed`が表示される
- セッションがRunning状態にならない

#### C. 心拍数クエリ実行
コンソールで以下を確認：
- `Watch: Sample query found X recent samples`
- `Watch: Anchored query executed and running`
- `Watch: Observer query also started`

**0件の場合**：
- Apple Watchが手首に装着されているか確認
- 手首検出がオンか確認（設定 → パスコード）

#### D. HKLiveWorkoutBuilder（watchOS 9.0+）
コンソールで以下を確認：
- `Watch: Setting up HKLiveWorkoutBuilder`
- `Watch: HKLiveWorkoutBuilder collection started successfully`
- `Watch: HKLiveWorkoutBuilder collected data for X types`

**エラーの場合**：
- `Watch WARNING: Could not get associatedWorkoutBuilder`
- `Watch ERROR: Failed to begin collection`

### 4. デバッグフローチャート

```
開始
  ↓
Health data available? --No--> ERROR: 基本設定の問題
  ↓ Yes
権限状態は2? --No--> WARNING: 権限設定が必要
  ↓ Yes
セッションRunning? --No--> ERROR: セッション開始失敗
  ↓ Yes
サンプル取得? --No--> 心拍センサーの問題
  ↓ Yes
UI更新? --No--> スレッドの問題
  ↓ Yes
成功
```

## よくある問題と解決方法

### 問題1: 「Health data not available」
**原因**: HealthKitが利用できない
**解決**:
- デバイスの再起動
- watchOS/iOSのアップデート確認

### 問題2: 権限状態が1（拒否）
**原因**: ユーザーが権限を拒否
**解決**:
1. iPhoneのヘルスケアアプリ
2. 共有 → アプリとサービス
3. MuscleBuildingRecorder
4. すべてオン

### 問題3: サンプル数が0
**原因**: 心拍センサーがデータを生成していない
**解決**:
- Apple Watchを手首にしっかり装着
- 10-15秒待つ
- 腕を動かして測定を促す

### 問題4: HKLiveWorkoutBuilder失敗
**原因**: watchOS 9.0未満または初期化エラー
**解決**:
- watchOSバージョン確認
- フォールバック（HKAnchoredObjectQuery）が動作しているか確認

## ログ収集スクリプト

実機でのログを収集する場合：

```bash
# Xcodeコンソールから手動でコピー、または
# Console.appを使用：
1. Console.appを開く
2. デバイス → Apple Watch
3. フィルター: "Watch:"
4. アプリ実行
5. ログをエクスポート
```

## 期待される結果

正常に動作した場合：
1. ワークアウト開始後10-15秒で心拍数表示
2. 5-10秒ごとに値が更新
3. Apple Watchの心拍数表示と一致

## 最終確認事項

- [ ] HealthKit権限が許可されている
- [ ] Apple Watchが手首に装着されている
- [ ] 手首検出がオンになっている
- [ ] ワークアウトセッションが開始されている
- [ ] コンソールにエラーログがない
- [ ] 心拍数が表示される

## サポート

問題が解決しない場合、以下の情報を収集してください：
1. Xcodeコンソールの全ログ
2. watchOSバージョン
3. Apple Watchモデル
4. 設定のスクリーンショット