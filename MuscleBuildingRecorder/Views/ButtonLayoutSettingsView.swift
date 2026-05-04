//
//  ButtonLayoutSettingsView.swift
//  MuscleBuildingRecorder
//
//  メイン切替ボタン（休憩に移行 / 次のセットへ）の縦位置を選ぶ Pro 限定設定。
//  上部 / 中部 / 下部 の 3 択。
//

import SwiftUI

struct ButtonLayoutSettingsView: View {
    @EnvironmentObject var proUserManager: ProUserManager
    @StateObject private var manager = ButtonLayoutManager.shared
    @State private var showingPurchase = false

    var body: some View {
        Form {
            descriptionSection
            if proUserManager.isPro {
                positionSelectorSection
                previewSection
            } else {
                proLockedSection
            }
        }
        .navigationTitle("ボタン配置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPurchase) {
            PurchaseView()
        }
    }

    // MARK: - Description
    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("メイン切替ボタンの位置", systemImage: "rectangle.3.group")
                    .font(.headline)
                Text("「休憩に移行」「次のセットへ」の大ボタンを画面の上部・中部・下部のいずれかに配置できます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Position Selector (Pro)
    private var positionSelectorSection: some View {
        Section(header: Text("配置")) {
            Picker("位置", selection: Binding(
                get: { manager.config.mainButtonVerticalPosition },
                set: { manager.setMainButtonVerticalPosition($0) }
            )) {
                ForEach(MainButtonVerticalPosition.allCases) { position in
                    Label(position.displayName, systemImage: position.icon)
                        .tag(position)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preview
    private var previewSection: some View {
        Section(header: Text("プレビュー")) {
            previewBox
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)
                .padding(.vertical, 12)
        }
    }

    private var previewBox: some View {
        let position = manager.config.mainButtonVerticalPosition
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.7, green: 0.15, blue: 0.15),
                                 Color(red: 0.4, green: 0.08, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 0) {
                if position != .top { Spacer(minLength: 0) }

                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                    Text("休憩に移行")
                        .fontWeight(.bold)
                }
                .font(.callout)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                )

                if position != .bottom { Spacer(minLength: 0) }
            }
            .padding(.vertical, 14)
        }
        .frame(height: 200)
        .animation(.easeInOut(duration: 0.25), value: position)
    }

    // MARK: - Pro Locked Section
    private var proLockedSection: some View {
        Section {
            Button {
                showingPurchase = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pro 限定機能")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("ボタン配置のカスタマイズは Pro 版でご利用いただけます。タップしてアップグレード")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
