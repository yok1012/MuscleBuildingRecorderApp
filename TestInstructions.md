# 動作確認手順

## 🧪 Step 1: シンプル版でテスト

### 1. アプリエントリーポイントを一時的に変更

**MuscleBuildingRecorderApp.swift**を以下に変更してテスト：

```swift
import SwiftUI

@main
struct MuscleBuildingRecorderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentViewSimple() // ← シンプル版を使用
        }
    }
}
```

### 2. ビルド＆実行
- Cmd + R で実行
- シンプル版のUIが表示されるか確認

## ✅ シンプル版が動作したら

### Step 2: 段階的に機能を追加

#### A. 基本的なSessionManagerを追加
```swift
@main
struct MuscleBuildingRecorderApp: App {
    @StateObject private var sessionManager = SessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
}
```

#### B. HeartRateManagerを追加
```swift
@StateObject private var heartRateManager = HeartRateManager.shared

// ContentViewに追加
.environmentObject(heartRateManager)
```

#### C. DataControllerを追加
```swift
let dataController = DataController.shared

// ContentViewに追加
.environment(\.managedObjectContext, dataController.container.viewContext)
```

## 🔍 エラーが発生した場合

### エラー別対処法

1. **「Cannot find type 'SessionManager' in scope」**
   - SessionManager.swiftがTarget Membershipに含まれているか確認
   - ViewModelsグループを作成してファイルを追加

2. **「Cannot find type 'WorkoutPhase' in scope」**
   - WorkoutPhase.swiftをプロジェクトに追加

3. **Core Dataエラー**
   - WorkoutModel.xcdatamodeldがプロジェクトに追加されているか確認
   - Target Membershipを確認

## 📝 デバッグコード追加

各ファイルの先頭に以下を追加してデバッグ：

```swift
// SessionManager.swift
init() {
    print("✅ SessionManager initialized")
}

// HeartRateManager.swift
init() {
    print("✅ HeartRateManager initialized")
}

// DataController.swift
init() {
    print("✅ DataController initialized")
    // 既存のコード...
}
```

## 🎯 最終確認

1. コンソールに初期化メッセージが表示される
2. TabViewが表示される
3. MainTimerViewが表示される
4. タイマーが動作する
5. 状態遷移が正しく動作する

## 💡 Tips

- **Previewではなく実機/シミュレータで確認**
- **Clean Build Folder (Cmd+Shift+K) を定期的に実行**
- **エラーメッセージをコンソールで確認**