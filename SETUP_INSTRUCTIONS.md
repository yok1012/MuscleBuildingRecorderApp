# Xcodeプロジェクト設定手順

## 🔧 UIが表示されない問題の解決方法

### 1. Xcodeプロジェクトのクリーンアップ
```bash
# Xcodeで以下を実行
1. Product → Clean Build Folder (Cmd + Shift + K)
2. Xcodeを完全に終了
3. DerivedDataを削除:
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
4. Xcodeを再起動
```

### 2. ファイルの追加確認

Xcodeのナビゲーターで以下の構造になっているか確認：

```
MuscleBuildingRecorder/
├── MuscleBuildingRecorderApp.swift ✅
├── ContentView.swift ✅
├── Views/
│   ├── MainTimerView.swift
│   ├── ExerciseInputSheet.swift
│   ├── SessionSummaryView.swift
│   ├── SettingsView.swift
│   └── HistoryView.swift
├── ViewModels/
│   └── SessionManager.swift
├── Services/
│   ├── HeartRateService.swift
│   ├── HeartRateManager.swift
│   ├── HealthKitHeartRateService.swift
│   ├── BLEHeartRateService.swift
│   └── AirPodsHeartRateService.swift
├── Data/
│   └── DataController.swift
├── Models/
│   ├── WorkoutPhase.swift
│   └── WorkoutModel.xcdatamodeld
├── LiveActivity/
│   ├── WorkoutAttributes.swift
│   ├── WorkoutLiveActivity.swift
│   └── LiveActivityManager.swift
└── Utils/
    ├── CSVExporter.swift
    └── JSONExporter.swift
```

### 3. ファイルを正しく追加する手順

1. **Xcodeで「File → Add Files to "MuscleBuildingRecorder"」を選択**
2. MuscleBuildingRecorderフォルダを選択
3. 以下のオプションを確認：
   - ✅ Copy items if needed（チェック不要、既にコピー済み）
   - ✅ Create groups
   - ✅ MuscleBuildingRecorder（ターゲット）

### 4. Target Membershipの確認

各.swiftファイルを選択して、右パネルの「Target Membership」で：
- ✅ MuscleBuildingRecorder にチェック

### 5. Build Settingsの確認

1. プロジェクトを選択
2. MuscleBuildingRecorderターゲットを選択
3. Build Settings → Swift Compiler - Language
   - Swift Language Version: Swift 5

### 6. Info.plistの確認

Info.plistに以下が追加されているか確認：
- Privacy - Health Share Usage Description
- Privacy - Health Update Usage Description
- Privacy - Bluetooth Always Usage Description
- NSSupportsLiveActivities: YES

### 7. 実行とデバッグ

1. **シミュレータを選択**（iPhone 15 Pro推奨）
2. **Run (Cmd + R)**
3. **コンソールでエラーを確認**

### 8. もしまだ動かない場合

#### A. 手動でファイルをグループ化
```
1. Xcodeで既存のファイルを削除（Remove Reference）
2. 新しいグループを作成（右クリック → New Group）
3. ファイルを1つずつ追加
```

#### B. 新規プロジェクトの作成
```
1. 新しいXcodeプロジェクトを作成
2. iOS App → SwiftUI → Include Core Data ✅
3. 作成したファイルをコピー
4. CapabilitiesとInfo.plistを設定
```

## 🔍 デバッグ確認ポイント

### ContentViewが正しく呼ばれているか確認
```swift
// ContentView.swiftの先頭に追加してデバッグ
struct ContentView: View {
    init() {
        print("✅ ContentView initialized")
    }
    // ...
}
```

### MainTimerViewが表示されているか確認
```swift
// MainTimerView.swiftに追加
var body: some View {
    VStack {
        Text("DEBUG: MainTimerView")
        // 既存のコード...
    }
    .onAppear {
        print("✅ MainTimerView appeared")
    }
}
```

## 💡 よくある問題と解決策

| 問題 | 解決策 |
|------|--------|
| ファイルが見つからない | Target Membershipを確認 |
| UIが古いまま | Clean Build & DerivedData削除 |
| クラッシュする | Core Dataモデルファイルを確認 |
| HealthKitエラー | Capabilitiesを確認 |

## 📱 実行確認チェックリスト

- [ ] Clean Build Folder実行済み
- [ ] DerivedData削除済み
- [ ] すべてのファイルがTarget Membershipに含まれている
- [ ] Core Dataモデルがプロジェクトに追加されている
- [ ] Info.plistに必要な権限が追加されている
- [ ] Capabilitiesが設定されている
- [ ] 実機またはシミュレータで実行（Previewではない）