# MuscleBuildingRecorder - アプリケーション状態レポート

## 📱 アプリ概要

**MuscleBuildingRecorder（筋トレ記録アプリ）**は、iOS/watchOS対応のワークアウトトラッキングアプリケーションです。リアルタイム心拍数モニタリング、モーションセンサーデータ収集、ワークアウトフェーズ管理、Core Dataによる永続化、Dynamic Island対応のLive Activitiesなどの機能を提供します。

## ✅ 実装済み機能

### 1. 基本機能
- **Work/Restタイマー機能**
  - 筋トレ（Work）と休憩（Rest）のフェーズ管理
  - サイクルカウント機能
  - フェーズごとの経過時間表示
  - 合計ワークアウト時間と休憩時間の個別追跡

- **エクササイズ記録**
  - カテゴリー別エクササイズ管理（胸、背中、脚など）
  - 負荷と回数の記録
  - カスタム単位対応（kg、回、秒など）
  - セット毎のメモ機能

### 2. 心拍数モニタリング
- **マルチソース対応**
  - HealthKit（Apple Watch）
  - Bluetooth LE心拍計
  - AirPods Pro心拍センサー
- **リアルタイム統計**
  - 平均、最大、最小心拍数
  - 心拍数勾配（回復率）計算
  - 10秒スライディングウィンドウによる傾き計算

### 3. センサーデータ収集
- **Apple Watchモーションセンサー**
  - 加速度センサー（3軸）
  - ジャイロスコープ（3軸）
  - デバイスモーション（姿勢、クォータニオン）
- **サンプリングレート選択**（25/50/100 Hz）
- **CSV形式での日次ファイル保存**
- **バッチ送信による電池最適化**（0.5秒間隔）

### 4. データエクスポート
- **CSV/JSON形式対応**
  - セッションサマリー
  - 詳細レコード
  - 心拍数ログ
  - センサーデータ（JSON形式で埋め込み）
- **複数日データの一括エクスポート**
- **ShareSheet経由での共有**

### 5. iPhone-Watch連携
- **双方向通信**
  - WatchConnectivityによるリアルタイム同期
  - コマンド送信（start/stop/pause/resume）
  - フェーズ変更の同期
  - 心拍数データの送信
- **オフライン対応**
  - updateApplicationContextによるキュー送信
  - 一時ファイル保存と自動再送

### 6. UI/UX機能
- **Live Activities（Dynamic Island）**
  - 現在のフェーズ表示
  - 経過時間
  - リアルタイム心拍数
- **watchOS専用UI**
  - 大きなボタンによる操作性向上
  - フェーズに応じた動的レイアウト
  - デバッグ情報表示（開発ビルドのみ）

### 7. バックグラウンド実行
- **HKWorkoutSessionベース**
  - ワークアウト中の継続実行
  - バックグラウンドでのセンサーデータ収集
  - 心拍数モニタリングの継続

## 🔧 最近の修正内容（2024年11月）

### 同期問題の修正
1. **Watch側タイマーの独立起動** ✅
   - Watch単体でワークアウト開始時にタイマーが正常に動作するよう修正
   - `togglePause()`の競合を解消

2. **iPhone→Watchタイマー制御** ✅
   - iPhoneからのフェーズ変更コマンドがWatch側タイマーに反映されるよう修正
   - `sendPhaseChange()`メソッドの実装

3. **センサーデータのセッションエクスポート** ✅
   - CSVエクスポートにセンサーデータ列を追加
   - JSON形式でのセンサーデータ埋め込み

4. **メモリリーク対策** ✅
   - weak self参照の追加
   - バッファサイズ制限（100サンプル）
   - セッション終了時のクリーンアップ

### ビルドエラーの修正
- FileHandle API廃止メソッドの更新
- Combineフレームワークインポートの追加
- 重複プロパティ定義の解消
- 型推論エラーの修正

## 📊 技術スタック

- **言語**: Swift 5.0
- **フレームワーク**: SwiftUI, HealthKit, CoreBluetooth, CoreMotion, ActivityKit, WatchConnectivity, Combine, Core Data
- **最小OS要件**: iOS 17.0+, watchOS 10.0+
- **開発環境**: Xcode 16.0.1+
- **アーキテクチャ**: MVVM + シングルトンマネージャー

## ⚠️ 既知の課題

### 1. 軽微な警告
- 廃止予定APIの使用（影響なし）
  - HKWorkoutSession.start() (watchOS 5.0で廃止)
  - LiveActivity関連API (iOS 16.2で更新)
- 未使用変数の警告（機能に影響なし）

### 2. 潜在的な改善点
- **大容量データ処理**
  - 長時間セッションでのセンサーデータ処理の最適化余地
  - メモリ使用量のさらなる削減可能性

- **UI/UXの改善余地**
  - iPad対応
  - ダークモード最適化
  - アクセシビリティ機能の強化

- **データ管理**
  - iCloud同期機能の追加
  - データバックアップ/リストア機能
  - 履歴データの可視化強化

### 3. テスト関連
- 単体テストカバレッジの向上が必要
- 統合テストの追加
- パフォーマンステストの実装

## 🚀 今後の開発候補

### 短期目標
1. **エクササイズライブラリの拡充**
   - プリセットエクササイズの追加
   - カスタムエクササイズの作成機能
   - エクササイズ画像/動画の追加

2. **分析機能の強化**
   - トレーニング履歴のグラフ表示
   - 進捗トラッキング
   - パフォーマンス指標の計算

3. **ソーシャル機能**
   - トレーニング記録の共有
   - 友達とのチャレンジ機能
   - リーダーボード

### 中長期目標
1. **AI/ML機能**
   - フォーム分析（センサーデータ活用）
   - トレーニング推奨機能
   - 疲労度予測

2. **プラットフォーム拡張**
   - iPad最適化
   - Mac Catalyst対応
   - visionOS対応検討

3. **外部連携**
   - 他のフィットネスアプリとの連携
   - ジム機器との接続
   - 栄養管理アプリとの統合

## 📈 パフォーマンス指標

### ビルド状態
- **iOS App**: ✅ ビルド成功
- **Watch App**: ✅ ビルド成功
- **警告数**: 約15件（全て軽微）
- **エラー数**: 0件

### メモリ使用量
- **センサーデータバッファ**: 最大100サンプル（約8KB）
- **心拍数ログ**: メモリ内保持（セッション終了時クリア）
- **CSVファイル**: 日次ローテーション

### 通信効率
- **バッチ送信間隔**: 0.5秒
- **最大ファイル転送サイズ**: 50MB
- **フォールバック機構**: 3段階（リアルタイム→キュー→ファイル）

## 🔐 セキュリティとプライバシー

### 実装済み対策
- HealthKit認証必須
- ローカルストレージのみ（クラウド同期なし）
- センサーデータの暗号化なし（要改善）

### 必要な権限
- **HealthKit**: 心拍数の読み取り/ワークアウトの書き込み
- **Bluetooth**: 心拍計とAirPods接続
- **Motion**: センサーデータ収集
- **Live Activities**: Dynamic Island表示

## 📝 開発者向けメモ

### デバッグ方法
1. **Watch側デバッグ**
   - ContentViewのデバッグセクション確認
   - "Manual HR"ボタンで心拍数取得テスト
   - WorkoutManagerのdebugMessage確認

2. **通信デバッグ**
   - WatchDebugViewで接続状態確認
   - コンソールログでメッセージ送受信確認
   - isReachableステータスチェック

3. **センサーデータ確認**
   - Documents/SensorLogs/内のCSVファイル
   - MultiDayExportViewでデータエクスポート
   - recentSamplesでリアルタイム表示

### ビルドコマンド
```bash
# iOS App
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme MuscleBuildingRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Watch App
xcodebuild -project MuscleBuildingRecorder.xcodeproj \
  -scheme "MuscleBuildingRecorderWatchTrue Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  build
```

## 📌 重要な注意事項

1. **Core Dataスキーマ変更時**
   - 必ず新バージョンを作成
   - 既存バージョンは変更禁止
   - マイグレーション処理の実装必須

2. **Watch通信**
   - isReachable = Watchが手首に装着、ロック解除、アプリフォアグラウンド時のみ
   - バックグラウンドではupdateApplicationContext使用
   - 大容量データはtransferFileを使用

3. **メモリ管理**
   - センサーデータは100サンプルまで
   - ファイル転送は50MB制限
   - weak selfを必ず使用

---
*最終更新: 2024年11月2日*
*バージョン: 1.0.0*