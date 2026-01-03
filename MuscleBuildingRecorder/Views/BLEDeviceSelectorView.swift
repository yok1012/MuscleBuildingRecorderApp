//
//  BLEDeviceSelectorView.swift
//  MuscleBuildingRecorder
//
//  Bluetooth心拍計デバイスを検索・選択するビュー
//

import SwiftUI

struct BLEDeviceSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var bleService: BLEHeartRateService

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ステータス表示
                statusHeader

                // デバイスリスト
                deviceList

                // エラー表示
                if let error = bleService.lastError {
                    errorBanner(error)
                }
            }
            .navigationTitle("心拍計を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        bleService.stopScanning()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if bleService.isScanning {
                        Button("停止") {
                            bleService.stopScanning()
                        }
                    } else {
                        Button("再スキャン") {
                            bleService.startScanning()
                        }
                    }
                }
            }
            .onAppear {
                // 画面表示時にスキャン開始
                if !bleService.isScanning && bleService.connectionState != .connected {
                    bleService.startScanning()
                }
            }
            .onDisappear {
                bleService.stopScanning()
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 8) {
            if bleService.isScanning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("心拍計を検索中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if bleService.connectionState == .connecting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("接続中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if bleService.connectionState == .connected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("接続完了: \(bleService.connectedDeviceName ?? "不明")")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                .padding()
            } else if bleService.discoveredDevices.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("心拍計が見つかりません")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("心拍計の電源がオンになっていることを確認してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var deviceList: some View {
        List {
            if !bleService.discoveredDevices.isEmpty {
                Section(header: Text("検出されたデバイス")) {
                    ForEach(bleService.discoveredDevices) { device in
                        deviceRow(device)
                    }
                }
            }

            // 接続中のデバイス情報
            if bleService.connectionState == .connected,
               let deviceName = bleService.connectedDeviceName {
                Section(header: Text("接続中のデバイス")) {
                    HStack {
                        Image(systemName: "heart.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(deviceName)
                                .font(.headline)
                            Text("接続済み")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        Spacer()

                        Button("切断") {
                            bleService.disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }
            }

            // ヘルプセクション
            Section(header: Text("ヒント")) {
                VStack(alignment: .leading, spacing: 8) {
                    tipRow(icon: "1.circle", text: "心拍計を装着し、電源を入れてください")
                    tipRow(icon: "2.circle", text: "iPhoneのBluetoothがオンになっていることを確認")
                    tipRow(icon: "3.circle", text: "他のアプリで心拍計を使用中の場合は切断してください")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func deviceRow(_ device: DiscoveredBLEDevice) -> some View {
        Button(action: {
            bleService.connectToDevice(device)
        }) {
            HStack {
                Image(systemName: "heart.circle")
                    .foregroundColor(.red)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(signalStrengthText(rssi: device.rssi))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 信号強度インジケーター
                signalStrengthIndicator(rssi: device.rssi)
            }
        }
        .disabled(bleService.connectionState == .connecting)
    }

    private func signalStrengthText(rssi: Int) -> String {
        switch rssi {
        case -50...0:
            return "信号: 非常に強い"
        case -60 ..< -50:
            return "信号: 強い"
        case -70 ..< -60:
            return "信号: 良好"
        case -80 ..< -70:
            return "信号: 弱い"
        default:
            return "信号: 非常に弱い"
        }
    }

    private func signalStrengthIndicator(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(signalBarColor(rssi: rssi, barIndex: index))
                    .frame(width: 4, height: CGFloat(6 + index * 4))
            }
        }
    }

    private func signalBarColor(rssi: Int, barIndex: Int) -> Color {
        let strength: Int
        switch rssi {
        case -50...0:
            strength = 4
        case -60 ..< -50:
            strength = 3
        case -70 ..< -60:
            strength = 2
        case -80 ..< -70:
            strength = 1
        default:
            strength = 0
        }

        return barIndex < strength ? .green : .gray.opacity(0.3)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(text)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
    }
}
