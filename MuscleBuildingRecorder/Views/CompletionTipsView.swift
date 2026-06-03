//
//  CompletionTipsView.swift
//  MuscleBuildingRecorder
//
//  セッション完了画面の後に表示するヒント画面。アプリでできることを
//  5枚程度のカードで順送り（ページング）表示する。全モード共通。
//  「次回から表示しない」トグル（@AppStorage("hideCompletionTips")）で抑止可能。
//

import SwiftUI

struct Tip: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let accent: Color
}

struct CompletionTipsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hideCompletionTips") private var hideCompletionTips = false
    @State private var page = 0

    /// ヒント内容（編集はここ1か所）
    private let tips: [Tip] = [
        Tip(icon: "heart.fill",
            title: "リアルタイム心拍数",
            description: "Apple Watch・Bluetooth胸ベルト・AirPodsから心拍を取得し、運動強度を可視化できます。",
            accent: .red),
        Tip(icon: "timer",
            title: "休憩タイマー＆通知",
            description: "休憩時間を自動計測。目安時間で予鈴・本鈴の通知が鳴り、+30秒のスヌーズも可能です。",
            accent: .blue),
        Tip(icon: "book.fill",
            title: "勉強・仕事モード",
            description: "筋トレだけでなく、勉強や仕事の集中時間も同じ操作で記録できます。",
            accent: .indigo),
        Tip(icon: "calendar",
            title: "履歴ダッシュボード",
            description: "履歴タブの「ダッシュボード」で、カレンダーとグラフから日々の活動を振り返れます。",
            accent: .green),
        Tip(icon: "square.stack.3d.up.fill",
            title: "プリセット＆エクスポート",
            description: "よく使うメニューをプリセット化してワンタップ開始。記録はCSV/JSONで書き出せます。",
            accent: .orange)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TabView(selection: $page) {
                    ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                        TipCard(tip: tip)
                            .tag(index)
                            .padding(.horizontal)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Toggle("次回から表示しない", isOn: $hideCompletionTips)
                    .padding(.horizontal)
                    .font(.subheadline)

                Button(action: { dismiss() }) {
                    Text(page >= tips.count - 1 ? LocalizedStringKey("完了") : LocalizedStringKey("閉じる"))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor)
                        )
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .navigationTitle("ヒント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct TipCard: View {
    let tip: Tip

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(tip.accent.opacity(0.15))
                    .frame(width: 140, height: 140)
                Image(systemName: tip.icon)
                    .font(.system(size: 60))
                    .foregroundColor(tip.accent)
            }
            VStack(spacing: 12) {
                Text(tip.title)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(tip.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
