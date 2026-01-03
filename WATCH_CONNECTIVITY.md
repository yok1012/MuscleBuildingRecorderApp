# Apple Watch連携機能ドキュメント

## 概要

MuscleBuildingRecorderアプリは、WatchConnectivityフレームワークを使用してiPhoneとApple Watch間の双方向通信を実現しています。この連携により、以下の機能を提供します：

- リアルタイム心拍数同期
- ワークアウトセッション制御
- モーションセンサーデータ収集
- フェーズ（Work/Rest）同期
- 時間情報の双方向同期

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────────┐
│                         iPhone側                                │
├─────────────────────────────────────────────────────────────────┤
│  SessionManager ←→ WatchConnectivityService ←→ WCSession       │
│        ↓                    ↓                                   │
│  HeartRateManager     SensorLogManager                          │
│        ↓                    ↓                                   │
│  LiveActivityManager   CSV Files                                │
└─────────────────────────────────────────────────────────────────┘
                              ↑↓ WCSession通信
┌─────────────────────────────────────────────────────────────────┐
│                        Apple Watch側                            │
├─────────────────────────────────────────────────────────────────┤
│  ContentView ←→ WorkoutManager ←→ WCSession                     │
│                       ↓                                         │
│               HKWorkoutSession                                  │
│                       ↓                                         │
│  WatchMotionStreamer ←→ CMMotionManager                         │
└─────────────────────────────────────────────────────────────────┘
```

## 通信プロトコル

### メッセージタイプ

```swift
enum WatchMessageType: String {
    case wakeUp = "wakeUp"           // Watchをウェイクアップ
    case heartRate = "heartRate"     // 心拍数データ
    case workoutState = "workoutState" // ワークアウト状態
    case phaseChange = "phaseChange"   // フェーズ変更
    case exerciseChange = "exerciseChange" // エクササイズ変更
    case command = "command"         // コマンド
}
```

### ワークアウト状態

```swift
enum WatchWorkoutState: String {
    case idle = "idle"       // アイドル状態
    case running = "running" // ワークアウト中
    case paused = "paused"   // 一時停止中
    case ended = "ended"     // 終了
}
```

## 通信方式

### 1. リアルタイムメッセージ (`sendMessage`)

iPhoneとWatchが**到達可能な場合**に使用される低遅延通信：

```swift
// iPhone → Watch: ワークアウト開始コマンド
session.sendMessage(["command": "start"], replyHandler: nil, errorHandler: nil)

// Watch → iPhone: 心拍数送信
session.sendMessage([
    "type": "heartRate",
    "heartRate": heartRate,
    "timestamp": Date().timeIntervalSince1970
], replyHandler: nil, errorHandler: nil)
```

**到達可能の条件:**
- Watchが手首に装着されている
- Watchのロックが解除されている
- アプリがフォアグラウンドにある

### 2. アプリケーションコンテキスト (`updateApplicationContext`)

到達不可能な場合のフォールバック。最新の状態を保持：

```swift
try session.updateApplicationContext([
    "workoutState": state.rawValue,
    "heartRate": heartRate,
    "elapsedTime": elapsedTime,
    "totalWorkTime": totalWorkTime,
    "totalRestTime": totalRestTime,
    "timestamp": Date().timeIntervalSince1970
])
```

### 3. ファイル転送 (`transferFile`)

センサーデータなど大容量データの転送に使用：

```swift
session.transferFile(tempFileURL, metadata: [
    "type": "sensorData",
    "sensorType": sensorType.rawValue,
    "sampleCount": samples.count
])
```

## iPhone側実装 (WatchConnectivityService)

### 主要プロパティ

| プロパティ | 型 | 説明 |
|-----------|----|----|
| `shared` | WatchConnectivityService | シングルトンインスタンス |
| `watchHeartRate` | Double | Watchからの心拍数 |
| `isWatchConnected` | Bool | Watch接続状態 |
| `watchStatus` | String | Watch状態の説明文 |
| `watchWorkoutState` | WatchWorkoutState | ワークアウト状態 |
| `watchElapsedTime` | TimeInterval | 経過時間 |

### 主要メソッド

#### ワークアウト制御

```swift
// ワークアウト開始
func startWatchWorkout()

// ワークアウト停止
func stopWatchWorkout()

// 一時停止
func pauseWatchWorkout()

// 再開
func resumeWatchWorkout()
```

#### フェーズ変更

```swift
func sendPhaseChange(
    phase: String,
    cycleIndex: Int,
    totalWorkTime: TimeInterval,
    totalRestTime: TimeInterval,
    elapsedTime: TimeInterval,
    currentPhaseTime: TimeInterval,
    previousPhase: String?,
    previousPhaseDuration: TimeInterval?
)
```

#### エクササイズ変更

```swift
func sendExerciseChange(category: String, exercise: String)
```

### デリゲートメソッド（受信）

```swift
// メッセージ受信
func session(_ session: WCSession, didReceiveMessage message: [String: Any])

// アプリケーションコンテキスト受信
func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any])

// ファイル受信
func session(_ session: WCSession, didReceive file: WCSessionFile)
```

## Watch側実装 (WorkoutManager)

### 主要プロパティ

| プロパティ | 型 | 説明 |
|-----------|----|----|
| `isWorkoutActive` | Bool | ワークアウトアクティブ状態 |
| `isPaused` | Bool | 一時停止状態 |
| `heartRate` | Double | 現在の心拍数 |
| `elapsedTime` | TimeInterval | 経過時間 |
| `currentPhaseTime` | TimeInterval | 現在フェーズの時間 |
| `totalWorkTime` | TimeInterval | 合計ワーク時間 |
| `totalRestTime` | TimeInterval | 合計レスト時間 |
| `currentPhase` | String | 現在のフェーズ |

### ワークアウト制御

```swift
// ワークアウト開始
func startWorkout()

// ワークアウト終了
func endWorkout()

// 一時停止/再開トグル
func togglePause()

// フェーズ設定
func setPhase(_ phase: String)
```

### 心拍数モニタリング

3段階のフォールバック戦略を実装：

1. **HKAnchoredObjectQuery**: プライマリ
2. **HKObserverQuery**: セカンダリ
3. **ポーリング**: 最終手段

```swift
func activateHeartRateMonitoring()
func stopHeartRateMonitoring()
func fetchMostRecentHeartRate(span: TimeInterval)
```

### iPhone通知

```swift
// 心拍数送信（スロットリング: 1秒間隔）
func sendHeartRateToPhone(_ hr: Double)

// ワークアウトコマンド送信
func sendWorkoutCommandToPhone(_ command: String)

// コンテキスト付きコマンド送信
func sendWorkoutCommandToPhoneWithContext(
    _ command: String,
    previousPhase: String?,
    previousPhaseDuration: TimeInterval?
)

// ワークアウト状態通知（5秒通常/3秒強制）
func notifyPhoneOfWorkout(
    heartRate: Double,
    elapsed: TimeInterval,
    state: String,
    force: Bool
)
```

## センサーデータ収集 (WatchMotionStreamer)

### センサータイプ

```swift
enum SensorType: String, CaseIterable {
    case accelerometer = "accel"     // 加速度センサー
    case gyroscope = "gyro"          // ジャイロスコープ
    case deviceMotion = "motion"     // デバイスモーション（統合）
}
```

### 設定可能なパラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| サンプリングレート | 25Hz | 25/50/100Hzから選択可能 |
| バッファサイズ | 1000サンプル | 約80KB |
| バッチ送信間隔 | 0.5秒 | バッテリー最適化 |

### データフォーマット

```json
{
  "type": "sensorData",
  "timestamp": 1700000000000,
  "accel_x": 0.01,
  "accel_y": -0.02,
  "accel_z": 0.98,
  "gyro_x": 0.001,
  "gyro_y": -0.002,
  "gyro_z": 0.003
}
```

### 使用方法

```swift
// 開始
WatchMotionStreamer.shared.start(
    rateHz: 50,
    sensors: [.accelerometer, .gyroscope]
)

// 停止
WatchMotionStreamer.shared.stop()
```

## 時間同期

双方向の時間同期により、iPhoneとWatch間でワークアウト時間を正確に維持：

### iPhone → Watch

```swift
// フェーズ変更時に時間情報を含めて送信
sendPhaseChange(
    phase: "work",
    cycleIndex: 1,
    totalWorkTime: 120.0,
    totalRestTime: 60.0,
    elapsedTime: 180.0,
    currentPhaseTime: 30.0,
    previousPhase: "rest",
    previousPhaseDuration: 60.0
)
```

### Watch → iPhone

```swift
// Watch側での操作時に時間情報を含めて送信
sendWorkoutCommandToPhoneWithContext(
    "toggle",
    previousPhase: currentPhase,
    previousPhaseDuration: currentPhaseTime
)
```

## エラーハンドリング

### 接続状態チェック

```swift
func checkWatchAvailability(completion: @escaping (Bool) -> Void)
```

### エラー送信（Watch → iPhone）

```swift
func sendErrorToPhone(_ error: String)
```

### デバッグ

DEBUG ビルドでは `WatchDebugView` が利用可能：
- 接続状態表示
- 心拍数モニタリング状態
- 手動トリガーボタン

## 重要な実装上の注意

### 1. WCSessionDelegate の宣言

**重要**: iOS側では、WCSessionDelegateはクラス宣言時に直接準拠する必要があります。空のextensionで準拠を宣言すると、メソッドが正しく呼び出されません。

```swift
// 正しい実装
class WatchConnectivityService: NSObject, WCSessionDelegate {
    // デリゲートメソッドをここに実装
}

// 誤った実装（メッセージを受信できない）
class WatchConnectivityService: NSObject {
}
extension WatchConnectivityService: WCSessionDelegate {
    // 空のextension
}
```

### 2. スロットリング

過剰な通信を防ぐため、以下のスロットリングを実装：

| データ種類 | 最小間隔 |
|-----------|----------|
| 心拍数 | 1秒 |
| ワークアウト状態（通常） | 5秒 |
| ワークアウト状態（強制） | 3秒 |

### 3. メモリリーク防止

- タイマーの適切な解放
- weak self の使用
- 検証/ハートビートタイマーの禁止

## トラブルシューティング

### 心拍数が表示されない

1. HKWorkoutSession の状態が "Running" か確認
2. HealthKit認証が `.sharingAuthorized` か確認
3. Watch アプリの "Manual Trigger" ボタンを試行
4. `consecutiveEmptyResults` カウンターを監視

### メッセージが受信されない

1. `isReachable` プロパティを確認
2. WCSessionDelegate が正しく設定されているか確認
3. `updateApplicationContext` へのフォールバックを確認

### センサーデータが送信されない

1. CMMotionManager の可用性を確認
2. サンプリングレートが適切か確認（25-100Hz）
3. `lastError` プロパティを監視
4. 保留中ファイル数を確認

## 必要な権限

### iOS (Info.plist)

- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`

### watchOS (Info.plist)

- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`
- `NSMotionUsageDescription`
- `WKBackgroundModes`: `workout-processing`
- `WKCompanionAppBundleIdentifier`: `yokAppDev.MuscleBuildingRecorder`

## ファイル構成

```
iOS側:
MuscleBuildingRecorder/Services/WatchConnectivityService.swift

Watch側:
MuscleBuildingRecorderWatchTrue Watch App/
├── WorkoutManager.swift        # ワークアウト管理
├── WatchMotionStreamer.swift   # センサーデータ収集
└── ContentView.swift           # Watch UI
```

## 参考リンク

- [WatchConnectivity - Apple Developer Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [HKWorkoutSession - Apple Developer Documentation](https://developer.apple.com/documentation/healthkit/hkworkoutsession)
- [Core Motion - Apple Developer Documentation](https://developer.apple.com/documentation/coremotion)
