# Apple Watch 心拍数取得とiPhone同期の修正プラン

## 現在の問題点
1. **心拍数取得の問題**
   - WorkoutSessionは開始しているが、心拍数クエリが正しく動作していない
   - HKAnchoredObjectQueryが適切に設定されていない可能性
   - ワークアウト中でないとリアルタイム心拍数が取得できない

2. **iPhone同期の問題**
   - Watch Connectivityが実装されていない
   - タイマーの状態が同期されていない
   - 心拍数データがiPhoneに送信されていない

## 修正方針

### 1. Watch側の心拍数取得修正
- HKAnchoredObjectQueryの代わりにHKObserverQueryとHKSampleQueryの組み合わせを使用
- ワークアウトセッション開始時に心拍数の監視を確実に開始
- デバッグ用のサンプルデータ生成機能を追加

### 2. Watch Connectivity実装
- WCSessionを使用してiPhoneとWatchの通信を確立
- リアルタイムメッセージングでタイマー状態を同期
- 心拍数データの送信

### 3. 実装手順
1. WorkoutManagerに新しい心拍数クエリメソッドを追加
2. Watch ConnectivityのセットアップとiPhoneへのデータ送信
3. iPhone側でWatch Connectivityのレシーバーを実装
4. デバッグモードでのテスト機能追加