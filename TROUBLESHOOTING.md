# トラブルシューティングガイド

## 🚨 UIが表示されない問題の完全解決策

### 即座に試すべき手順

#### 1️⃣ Xcodeプロジェクトをクリーンアップ
```bash
# ターミナルで実行
cd ~/Library/Developer/Xcode
rm -rf DerivedData
```

#### 2️⃣ Xcodeで以下を実行
1. **Product → Clean Build Folder** (Cmd + Shift + K)
2. **Xcodeを完全に終了**
3. **Xcodeを再起動**
4. **プロジェクトを開く**

#### 3️⃣ ファイルの再追加
1. Xcodeのナビゲーターですべての.swiftファイルを選択
2. 右クリック → Delete → Remove Reference
3. File → Add Files to "MuscleBuildingRecorder"
4. MuscleBuildingRecorderフォルダを選択
5. Options:
   - ✅ Create groups
   - ✅ MuscleBuildingRecorder (target)

### 確実に動作させる方法

#### 方法A: 新規プロジェクト作成（推奨）

1. **新規プロジェクト作成**
   ```
   File → New → Project
   iOS → App
   Interface: SwiftUI
   Language: Swift
   Use Core Data: ✅
   ```

2. **ファイルをコピー**
   ```bash
   # 作成済みファイルを新プロジェクトにコピー
   cp -r MuscleBuildingRecorder/*.swift 新プロジェクト/
   cp -r MuscleBuildingRecorder/WorkoutModel.xcdatamodeld 新プロジェクト/
   ```

3. **Xcodeでファイルを追加**
   - File → Add Files
   - すべての.swiftファイルを選択
   - Core Dataモデルを追加

#### 方法B: 段階的実装

1. **まずContentViewSimpleで動作確認**
   ```swift
   // MuscleBuildingRecorderApp.swift
   @main
   struct MuscleBuildingRecorderApp: App {
       var body: some Scene {
           WindowGroup {
               ContentViewSimple()
           }
       }
   }
   ```

2. **動作したら本番コードに切り替え**

### コードが正しく動作しているか確認

#### デバッグプリントを追加
```swift
// MuscleBuildingRecorderApp.swift
@main
struct MuscleBuildingRecorderApp: App {
    init() {
        print("🚀 App Started")
    }
    // ...
}

// ContentView.swift
struct ContentView: View {
    init() {
        print("📱 ContentView Created")
    }
    // ...
}
```

### ファイル構成チェックリスト

```
✅ MuscleBuildingRecorder/
   ✅ MuscleBuildingRecorderApp.swift
   ✅ ContentView.swift
   ✅ MainTimerView.swift
   ✅ ExerciseInputSheet.swift
   ✅ SessionSummaryView.swift
   ✅ SettingsView.swift
   ✅ HistoryView.swift
   ✅ Data/
      ✅ DataController.swift
   ✅ ViewModels/
      ✅ SessionManager.swift
   ✅ Services/
      ✅ HeartRateManager.swift
      ✅ HeartRateService.swift
      ✅ HealthKitHeartRateService.swift
      ✅ BLEHeartRateService.swift
      ✅ AirPodsHeartRateService.swift
   ✅ Models/
      ✅ WorkoutPhase.swift
      ✅ WorkoutModel.xcdatamodeld
   ✅ Utils/
      ✅ CSVExporter.swift
      ✅ JSONExporter.swift
   ✅ LiveActivity files...
```

### エラー別対処法

| エラー | 原因 | 解決策 |
|--------|------|--------|
| Type 'XXX' has no member 'YYY' | インポート不足 | 必要なframeworkをimport |
| Cannot find type in scope | ファイル未追加 | Target Membershipを確認 |
| Thread 1: Fatal error | 初期化エラー | シングルトンの初期化を確認 |
| UI not updating | SwiftUI更新問題 | @StateObject/@EnvironmentObjectを確認 |

### 最終手段

#### 完全リセット方法
```bash
# 1. プロジェクトフォルダをバックアップ
cp -r MuscleBuildingRecorder MuscleBuildingRecorder_backup

# 2. Xcodeのキャッシュを完全削除
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/com.apple.dt.Xcode

# 3. Xcodeを再起動

# 4. 新規プロジェクトを作成

# 5. ファイルを一つずつ追加して動作確認
```

### サポート用コマンド

```bash
# ファイル一覧確認
find MuscleBuildingRecorder -name "*.swift" -type f | sort

# インポート確認
grep -h "^import" MuscleBuildingRecorder/*.swift | sort -u

# クラス/構造体定義確認
grep -h "^class\|^struct\|^enum" MuscleBuildingRecorder/*.swift
```

## 💡 それでも動かない場合

1. **ContentViewSimple.swift**を使って最小構成で動作確認
2. **コンソールログ**を確認してエラーメッセージを特定
3. **一つずつファイルを追加**して問題のあるファイルを特定
4. **新規プロジェクト**で最初から構築

## 📧 サポート

上記すべてを試しても動作しない場合は、以下の情報と共に質問してください：
- Xcodeのバージョン
- iOSシミュレータのバージョン
- コンソールのエラーメッセージ
- どの段階まで動作したか