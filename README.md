# MuscleBuildingRecorder - 筋トレ記録アプリ

## Xcodeプロジェクト設定手順

### 1. ファイル追加手順
Xcodeプロジェクトにファイルを追加:

1. **MuscleBuildingRecorder** グループに以下のファイルを追加:
   - `MainTimerView.swift`
   - `ExerciseInputSheet.swift`
   - `SessionSummaryView.swift`
   - `SettingsView.swift`
   - `HistoryView.swift`
   - `WorkoutAttributes.swift`
   - `WorkoutLiveActivity.swift`
   - `LiveActivityManager.swift`

2. **Models** グループを作成して追加:
   - `WorkoutPhase.swift`
   - `WorkoutModel.xcdatamodeld` (Core Dataモデル)

3. **Services** グループを作成して追加:
   - `HeartRateService.swift`
   - `HealthKitHeartRateService.swift`
   - `BLEHeartRateService.swift`
   - `AirPodsHeartRateService.swift`
   - `HeartRateManager.swift`

4. **ViewModels** グループを作成して追加:
   - `SessionManager.swift`

5. **Data** グループを作成して追加:
   - `DataController.swift`

6. **Utils** グループを作成して追加:
   - `CSVExporter.swift`
   - `JSONExporter.swift`

### 2. Capabilities設定
プロジェクト設定 → Signing & Capabilities:

1. **+ Capability** をクリックして追加:
   - HealthKit
   - Background Modes
     - ✅ Uses Bluetooth LE accessories
     - ✅ Background processing
   - App Groups (group.com.yourcompany.workouttracker)

### 3. Info.plist 追加項目
以下のキーを Info.plist に追加:

```xml
<key>NSHealthShareUsageDescription</key>
<string>このアプリはワークアウト中の心拍数データを読み取り、トレーニングの効果を可視化するためにHealthKitを使用します。</string>
<key>NSHealthUpdateUsageDescription</key>
<string>このアプリはワークアウトセッションをHealthKitに保存し、フィットネス記録を管理するために使用します。</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>このアプリはBluetooth心拍計と接続して、リアルタイムで心拍数を測定するために使用します。</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>このアプリはBluetooth Low Energy心拍計からデータを取得するために使用します。</string>
<key>NSSupportsLiveActivities</key>
<true/>
```

### 4. Build Settings
- Deployment Target: iOS 17.0
- Swift Language Version: 5.9

### 5. ビルドエラー対処
もしビルドエラーが発生した場合:

1. **Clean Build Folder**: Cmd + Shift + K
2. **Delete Derived Data**: ~/Library/Developer/Xcode/DerivedData を削除
3. **Reset Package Caches**: File → Packages → Reset Package Caches

### 6. watchOS アプリの設定
watchOSアプリはプロジェクトに含まれています。

#### Watch App アイコン設定
Watch Appのアイコンは以下の手順で設定されています：

1. **Assets.xcassets にアイコンを配置**
   - `MuscleBuildingRecorderWatchTrue Watch App/Assets.xcassets/AppIcon.appiconset/`
   - 1024x1024のマーケティング用アイコンから各サイズを自動生成
   - 必要なサイズ: 48, 55, 58, 87, 80, 88, 92, 100, 102, 108, 172, 196, 216, 234, 258px

2. **Info.plist の設定**
   - `CFBundleIconName`: AppIcon を指定
   - `CFBundleIconFiles`: AppIcon 配列を追加（watchOS必須）

3. **ビルド設定**
   - `GENERATE_INFOPLIST_FILE`: NO
   - `INFOPLIST_FILE`: "MuscleBuildingRecorderWatchTrue Watch App/Info.plist"
   - `ASSETCATALOG_COMPILER_APPICON_NAME`: AppIcon

4. **新しいアイコンの追加方法**
   ```bash
   # 1024x1024の画像から各サイズを生成
   cd "MuscleBuildingRecorderWatchTrue Watch App/Assets.xcassets/AppIcon.appiconset"
   sips -Z 48 AppIcon1024x1024.png --out AppIcon-48.png
   sips -Z 55 AppIcon1024x1024.png --out AppIcon-55.png
   # ... (他のサイズも同様)
   ```

#### Watch App トラブルシューティング
App Store アップロード時の「Missing Icons」エラーが発生した場合：
- Info.plist に `CFBundleIconFiles` があることを確認
- Assets.xcassets に全サイズのアイコンがあることを確認
- プロジェクトの File System Synchronized Group から Info.plist が除外されていることを確認

## 実行方法

### 開発用
1. Xcodeでプロジェクトを開く
2. スキーム選択で実機またはシミュレータを選択
3. Cmd + R でビルド＆実行

### App Store / TestFlight へのアップロード
1. **アーカイブ作成**
   ```bash
   # コマンドライン
   xcodebuild archive \
     -scheme "MuscleBuildingRecorder" \
     -configuration Release \
     -archivePath "./build/MuscleBuildingRecorder.xcarchive" \
     -destination 'generic/platform=iOS'
   ```

   または Xcode の Product → Archive を使用

2. **アーカイブの検証**
   - Xcode Organizer で「Distribute App」→「App Store Connect」を選択
   - 「Validate App」を実行して問題がないか確認

3. **TestFlight へアップロード**
   - 「Upload」を選択してアップロード
   - App Store Connect でビルドを確認

## プロジェクト構成

```
MuscleBuildingRecorder/
├── MuscleBuildingRecorder/          # iOSアプリ
│   ├── Models/                      # データモデル
│   ├── ViewModels/                  # ビューモデル
│   ├── Views/                       # ビューコンポーネント
│   ├── Services/                    # 心拍数サービス
│   ├── Utils/                       # ユーティリティ
│   ├── Data/                        # Core Data
│   └── Assets.xcassets/            # アセット
├── MuscleBuildingRecorderWatchTrue Watch App/  # watchOSアプリ
│   ├── WorkoutManager.swift        # ワークアウト管理
│   ├── ContentView.swift           # メインビュー
│   ├── Assets.xcassets/            # アイコン含む
│   └── Info.plist                  # Watch App設定
└── Shared/                          # 共有コード（将来用）
```

## 主要機能
- ✅ Work/Rest タイマー機能
- ✅ 心拍数測定（HealthKit/BLE/AirPods Pro）
- ✅ エクササイズ記録
- ✅ CSV/JSONエクスポート
- ✅ Live Activity対応
- ✅ watchOS連携
- ✅ リアルタイム心拍数モニタリング

## 技術仕様
- **iOS**: iOS 17.0+
- **watchOS**: watchOS 10.0+
- **言語**: Swift 5.0
- **フレームワーク**: SwiftUI, HealthKit, CoreBluetooth, ActivityKit
- **開発環境**: Xcode 16.0+

## 既知の問題と解決方法

### Watch App アイコン関連
**問題**: TestFlightアップロード時に「Missing Icons」エラー
**原因**: watchOSアプリのInfo.plistに`CFBundleIconFiles`が未設定、またはアイコン画像が不足
**解決方法**:
- Info.plistに`CFBundleIconFiles`配列を追加
- 全サイズのアイコン画像を生成（上記の手順参照）
- プロジェクト設定で`GENERATE_INFOPLIST_FILE = NO`に設定

### ビルドエラー
**問題**: Info.plist重複エラー
**原因**: File System Synchronized GroupにInfo.plistが含まれている
**解決方法**: project.pbxprojで`PBXFileSystemSynchronizedBuildFileExceptionSet`を追加してInfo.plistを除外

### 心拍数が取得できない
**問題**: HealthKitから心拍数が取得できない
**解決方法**:
- Info.plistにHealthKit使用許可の記述があることを確認
- iPhone/Apple Watchの設定でHealthKitへのアクセスを許可
- ワークアウトセッションが開始されていることを確認

## 更新履歴

### v1.0.0 (2025-10-18)
- 初期リリース
- iOS/watchOS アプリの実装
- Watch App アイコン設定の修正
- TestFlight アップロード対応

## ライセンス
このプロジェクトは個人開発プロジェクトです。

## 開発者
開発: @kiichiyokokawa