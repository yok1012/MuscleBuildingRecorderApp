# Watch→iPhone通信問題 修正テスト手順書

## 🔧 修正内容の概要

Apple Watchからの操作がiPhoneで受け付けられない問題を修正しました。

### 主な修正点：
1. **applicationContext更新の修正**
   - 読み取り専用プロパティを直接変更していた問題を修正
   - ユニークIDを追加して同じコマンドでも確実に更新されるように改善

2. **詳細なデバッグログの追加**
   - Watch側・iPhone側両方に詳細なログを追加
   - コマンドの送信・受信・実行の全段階を追跡可能に

3. **メッセージ処理の改善**
   - 直接送信（sendMessage）とキュー送信（applicationContext）の両方に対応
   - エラー時の自動フォールバック機構を強化

## 📱 ビルド状態

✅ **iOS App**: ビルド成功
✅ **Watch App**: ビルド成功

## 🧪 テスト手順

### 1. アプリの起動
1. Xcodeでプロジェクトを開く
2. iPhoneシミュレータでMuscleBuildingRecorderを実行
3. WatchシミュレータでMuscleBuildingRecorderWatchTrue Watch Appを実行

### 2. コンソールログの確認準備
Xcodeのコンソールで以下のログが表示されることを確認：
- `iPhone: WCSession activated`
- `Watch: WCSession activated`

### 3. Watch→iPhone通信テスト

#### テスト1: ワークアウト開始
1. **Watch側操作**: 「スタート」ボタンをタップ
2. **期待される動作**:
   - iPhone側でワークアウトが開始される
   - タイマーが動き始める
3. **確認するログ**:
   ```
   Watch: ✅ Command saved to applicationContext: startSession
   iPhone: ⚡️ Received application context update
   iPhone: ✅ Processing command from applicationContext: 'startSession'
   iPhone: 📱 Calling SessionManager.shared.startSession()
   SessionManager: 🎬 startSession() called
   ```

#### テスト2: フェーズ切り替え（筋トレ→休憩）
1. **Watch側操作**: 筋トレ中に「休憩へ」ボタンをタップ
2. **期待される動作**:
   - iPhone側でフェーズが休憩に切り替わる
   - タイマーがリセットされて休憩時間のカウント開始
3. **確認するログ**:
   ```
   Watch: Sending command via sendMessage: togglePhase (または applicationContext)
   iPhone: 📨 Received command message via direct sendMessage
   iPhone: 🔄 togglePhase() called
   SessionManager: 🔄 togglePhase() called
   ```

#### テスト3: フェーズ切り替え（休憩→筋トレ）
1. **Watch側操作**: 休憩中に「筋トレへ」ボタンをタップ
2. **期待される動作**:
   - iPhone側でフェーズが筋トレに切り替わる
   - サイクル数が+1される
3. **確認するログ**: テスト2と同様

#### テスト4: ワークアウト終了
1. **Watch側操作**: 「終了」ボタンをタップ
2. **期待される動作**:
   - iPhone側でワークアウトが終了
   - セッションサマリーが表示される
3. **確認するログ**:
   ```
   Watch: ✅ Command saved to applicationContext: endSession
   iPhone: 📱 Calling SessionManager.shared.endSession()
   SessionManager: 🛑 endSession() called
   ```

### 4. 通信失敗時のフォールバックテスト

#### テスト5: iPhoneアプリがバックグラウンドの場合
1. iPhoneアプリをバックグラウンドに移動
2. Watch側で「スタート」ボタンをタップ
3. **期待される動作**:
   - `Watch: iPhone not reachable, using applicationContext`のログ
   - iPhoneアプリをフォアグラウンドに戻すとコマンドが実行される

## 🐛 デバッグ情報の見方

### ログの記号の意味：
- ✅ 成功
- ❌ エラー
- ⚠️ 警告
- 🎯 実行中
- 📱 SessionManager呼び出し
- 📨 メッセージ受信
- ⚡️ applicationContext更新
- 🔧 コマンド処理
- 🚀 実行開始
- 🏁 実行完了

### 問題が起きた場合のチェックポイント：
1. **コマンドがWatch側から送信されているか**
   - `Watch: ✅ Command saved to applicationContext`が表示されるか
   - コマンドIDが生成されているか

2. **iPhoneがコマンドを受信しているか**
   - `iPhone: ⚡️ Received application context update`が表示されるか
   - contextのキーとコマンド内容が正しく表示されるか

3. **SessionManagerが呼ばれているか**
   - `SessionManager: [各メソッド名] called`が表示されるか
   - 現在のフェーズが正しく表示されるか

## 📝 トラブルシューティング

### 問題: Watchからの操作が反映されない
**解決策**:
1. 両アプリが起動していることを確認
2. WCSessionがactivatedになっていることを確認
3. applicationContextのcommandIdが変わっていることを確認

### 問題: "iPhone not reachable"が頻発
**解決策**:
1. iPhoneアプリがフォアグラウンドにあることを確認
2. シミュレータの場合、両方のシミュレータが起動していることを確認
3. 実機の場合、Watchが手首に装着されロック解除されていることを確認

### 問題: コマンドは受信するが実行されない
**解決策**:
1. SessionManagerの現在のフェーズを確認（idle以外でstartSessionは実行されない）
2. メインスレッドで実行されているか確認
3. Core Dataの保存エラーがないか確認

## 🎯 最終確認事項

以下のすべての操作がWatch側から正常に実行できることを確認：
- [ ] ワークアウト開始
- [ ] 筋トレ→休憩の切り替え
- [ ] 休憩→筋トレの切り替え
- [ ] ワークアウト終了
- [ ] 種目変更リクエスト

## 📊 修正前後の比較

### 修正前の問題：
- applicationContextの更新が正しく行われていなかった
- 同じコマンドの連続実行時に更新がトリガーされなかった
- デバッグ情報が不足していて問題箇所の特定が困難

### 修正後の改善：
- applicationContextを新規作成して確実に更新
- ユニークIDにより同じコマンドでも確実に処理
- 詳細なログで問題の特定が容易に

---

テスト実施日時: _______________
テスト実施者: _______________
テスト結果: _______________