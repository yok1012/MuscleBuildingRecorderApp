# Apple Watch 心拍数取得とiPhone同期 - 実装完了

## 実装した機能

### 1. Watch側の改善
- **HKObserverQuery**を使用した心拍数監視の実装
- **HKSampleQuery**による最新心拍数の取得
- ワークアウトセッション開始時の心拍数クエリ自動開始
- デバッグ情報の表示強化

### 2. Watch Connectivity実装
- **WCSession**を使用したiPhoneとWatchの双方向通信
- リアルタイムメッセージングによる心拍数データの送信
- タイマーコマンドの同期（開始、停止、一時停止、再開）

### 3. iPhone側の機能追加
- **WatchConnectivityService**クラスの新規作成
- Watch心拍数データの受信と表示
- タイマー操作のWatch同期
- デバッグビュー（WatchDebugView）の追加

## テスト手順

### 準備
1. iPhoneとApple Watchの両方で開発者モードを有効にする
2. Xcodeで両方のアプリをビルド・インストール

### Watch側でのテスト
1. Watch Appを起動
2. 「Start」ボタンをタップしてワークアウトを開始
3. デバッグ情報を確認：
   - **Session State**: "Running"になっているか
   - **Query Status**: "HR: XX"と心拍数が表示されるか
   - **Debug Message**: データの取得状態

### iPhone側でのテスト
1. iPhone Appを起動
2. **Debugタブ**（開発ビルドのみ表示）を開く
3. 以下を確認：
   - Watch接続状態（緑の●が表示される）
   - Watch心拍数の表示
   - 最終更新時刻

### 同期テスト
1. iPhone側のDebugタブから操作：
   - 「開始」ボタンでWatchワークアウト開始
   - 「停止」ボタンでWatchワークアウト停止
   - 「一時停止」「再開」ボタンで制御

2. Watch側から開始した場合：
   - iPhone側で心拍数データが自動受信される
   - リアルタイムで更新される

## トラブルシューティング

### 心拍数が取得できない場合
1. **HealthKitの権限確認**
   - iPhoneの設定 > プライバシー > ヘルスケア > MuscleBuildingRecorder
   - 「心拍数」の読み取り許可を確認

2. **Watch側の権限確認**
   - Watchの設定 > プライバシー > ヘルスケア
   - アプリの権限を確認

3. **ワークアウトセッションの確認**
   - Watchでワークアウトが「Running」状態か確認
   - Debug Messageで「Session RUNNING」と表示されているか

### 同期が取れない場合
1. **Bluetooth接続確認**
   - iPhoneとWatchのペアリングを確認
   - 両デバイスが近くにあることを確認

2. **Watch Connectivity状態**
   - iPhone側のDebugタブで接続状態を確認
   - 「Watch接続済み」と表示されているか

## ビルドエラーの対処

### アイコンエラー
- Watch AppのAssets.xcassetsにAppIconが正しく設定されているか確認
- 1024x1024のアイコンファイルが必要

### Info.plist関連
- WKApplication = YESが設定されているか確認
- WKCompanionAppBundleIdentifierが正しいか確認

## 今後の改善点
- バックグラウンドでの心拍数取得
- 履歴データの同期
- エラーハンドリングの強化
- UIの改善