# AirPods Pro 3 心拍数取得機能実装

## 概要
AirPods Pro 3からの心拍数取得機能を実装しました。現在AirPods Pro 3は未発売のため、シミュレーションモードを含む実装となっています。

## 実装内容

### 1. AirPodsHeartRateService
**ファイル**: `MuscleBuildingRecorder/Services/AirPodsHeartRateService.swift`

#### 主な機能
- CoreBluetoothを使用したBLE接続
- 標準的なBLE Heart Rate Service (UUID: 180D)のサポート
- AirPods特有のサービスUUIDへの対応準備
- AVAudioSessionを使用したAirPods検出
- シミュレーションモード（開発用）

#### 実装詳細
```swift
// 標準BLE心拍数サービス
private let heartRateServiceUUID = CBUUID(string: "180D")
private let heartRateCharacteristicUUID = CBUUID(string: "2A37")

// AirPods特有のサービス（仮定値）
private let airPodsServiceUUID = CBUUID(string: "FDB4")
```

### 2. HeartRateManager統合
**ファイル**: `MuscleBuildingRecorder/Services/HeartRateManager.swift`

既存のHeartRateManagerにAirPodsサービスを統合：
- 複数の心拍数ソースを管理
- 自動切り替え機能
- HealthKit、Bluetooth、AirPodsの3つのソースをサポート

### 3. UI実装
**ファイル**: `MuscleBuildingRecorder/Views/AirPodsConnectionView.swift`

#### UIコンポーネント
- 接続状態表示
- リアルタイム心拍数表示
- デバイス選択インターフェース
- 心拍数統計（平均、最大、最小）
- トレンド表示（上昇/下降）

## 使用方法

### 1. 通常の接続（実機AirPods Pro 3が利用可能な場合）

1. AirPods Pro 3をiPhoneにペアリング
2. アプリを起動し「心拍数モニター」画面を開く
3. デバイス選択で「AirPods Pro 3」を選択
4. 「接続」ボタンをタップ

### 2. シミュレーションモード（開発用）

```swift
// デバッグビルドで利用可能
#if DEBUG
// シミュレーションモードをオンにする
showSimulatedMode = true
#endif
```

シミュレーションモードでは、実際のデバイスなしでリアルな心拍数データを生成：
- 基準値: 70 BPM
- 変動: ±15 BPM（サイン波）
- ノイズ: ±3 BPM（ランダム）

## 技術仕様

### BLE心拍数データフォーマット
```
Byte 0: フラグ
  - Bit 0: 心拍数フォーマット (0=8bit, 1=16bit)
  - Bit 3: エネルギー消費データ有無
  - Bit 4: RR間隔データ有無

Byte 1-2: 心拍数値
  - 8bit: Byte 1のみ
  - 16bit: Byte 1-2 (リトルエンディアン)

Byte 3+: オプションデータ
  - エネルギー消費 (2 bytes)
  - RR間隔 (2 bytes × N)
```

### 接続フロー
1. Bluetooth電源状態確認
2. デバイススキャン（10秒タイムアウト）
3. AirPodsまたは心拍数サービスを持つデバイスを検出
4. 接続確立
5. サービス探索
6. 特性探索
7. 通知有効化
8. データ受信開始

## 注意事項

### 現在の制限
1. **AirPods Pro 3は未発売**
   - 実際のUUIDとプロトコルは製品リリース時に更新が必要
   - 現在は標準的なBLE Heart Rate Serviceを想定

2. **シミュレーションモード**
   - 開発とテスト用のみ
   - 実際のセンサーデータではない

3. **権限要件**
   - Bluetoothアクセス権限が必要
   - Info.plistに以下を追加：
   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>心拍数モニターとの接続に使用します</string>
   ```

### 将来の更新予定
1. 実際のAirPods Pro 3仕様への対応
2. Apple独自のプロトコルへの対応
3. より詳細な健康データ（SpO2、体温など）の取得
4. バッテリー残量表示
5. ファームウェアアップデート対応

## テスト方法

### ユニットテスト
```swift
// シミュレーションモードでのテスト
func testSimulatedHeartRate() async {
    let service = AirPodsHeartRateService()
    service.startSimulatedData()

    // 心拍数データが生成されることを確認
    let expectation = XCTestExpectation()
    service.heartRatePublisher
        .sink { heartRate in
            XCTAssert(heartRate >= 60 && heartRate <= 100)
            expectation.fulfill()
        }

    await fulfillment(of: [expectation], timeout: 5)
}
```

### 統合テスト
1. アプリを起動
2. AirPodsConnectionViewを開く
3. シミュレーションモードを有効化
4. 心拍数が表示されることを確認
5. 統計値（平均、最大、最小）が更新されることを確認

## トラブルシューティング

### 接続できない場合
1. Bluetooth権限を確認
2. Bluetoothがオンになっているか確認
3. デバイスが近くにあるか確認
4. デバイスが他のアプリに接続されていないか確認

### データが表示されない場合
1. 接続状態を確認
2. シミュレーションモードを試す
3. アプリを再起動
4. デバイスを再ペアリング

## まとめ

AirPods Pro 3の心拍数取得機能を先行実装しました。現在はシミュレーションモードで動作確認が可能です。実際の製品がリリースされた際には、最小限の変更で対応可能な設計となっています。