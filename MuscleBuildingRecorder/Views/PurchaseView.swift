//
//  PurchaseView.swift
//  MuscleBuildingRecorder
//
//  Pro版購入画面
//

import SwiftUI
import StoreKit

struct PurchaseView: View {
    @StateObject private var proUserManager = ProUserManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    featuresSection

                    if !proUserManager.products.isEmpty {
                        productsSection
                    } else {
                        noProductsView
                    }

                    legalSection
                }
                .padding()
            }
            .navigationTitle("筋トレ記録 Pro")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .alert("購入状態", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: proUserManager.purchaseState) { newState in
            handlePurchaseStateChange(newState)
        }
        .task {
            await proUserManager.loadProducts()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)

            Text("筋トレ記録 Pro")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("広告なしで快適なトレーニング体験を")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features Section
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pro版の特典")
                .font(.headline)
                .fontWeight(.semibold)

            FeatureRow(
                icon: "xmark.circle",
                title: "広告なし",
                description: "トレーニング完了時の広告をスキップ"
            )
            FeatureRow(
                icon: "bolt.fill",
                title: "即時リザルト表示",
                description: "トレーニング終了後すぐに結果を確認"
            )
            FeatureRow(
                icon: "heart.fill",
                title: "開発サポート",
                description: "今後のアップデート開発をサポート"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Products Section
    private var productsSection: some View {
        VStack(spacing: 16) {
            if proUserManager.isPro {
                purchasedView
            } else {
                // 商品を表示（月額を先に、買い切りを後に）
                ForEach(sortedProducts(), id: \.id) { product in
                    purchaseButton(for: product)
                }

                // 購入を復元ボタン
                restoreButton

                // サブスクリプション情報
                subscriptionTermsView
            }
        }
    }

    private func sortedProducts() -> [Product] {
        proUserManager.products.sorted { product1, product2 in
            // 月額サブスクを先に表示
            if product1.isMonthlySubscription && !product2.isMonthlySubscription {
                return true
            } else if !product1.isMonthlySubscription && product2.isMonthlySubscription {
                return false
            }
            return product1.price < product2.price
        }
    }

    private var purchasedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)

            Text("Pro版購入済み")
                .font(.headline)
                .foregroundColor(.green)

            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private func purchaseButton(for product: Product) -> some View {
        VStack(spacing: 8) {
            // 商品タイプの表示
            HStack {
                if product.isMonthlySubscription {
                    Label("月額サブスクリプション", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Label("買い切りライセンス", systemImage: "infinity")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }
            .padding(.horizontal)

            Button(action: {
                Task {
                    await proUserManager.purchase(product)
                }
            }) {
                HStack {
                    if case .purchasing = proUserManager.purchaseState {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        VStack(spacing: 4) {
                            Text(product.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(product.displayPrice)
                                .font(.headline)
                                .fontWeight(.bold)

                            if product.subscription != nil {
                                Text(getPeriodText(for: product))
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(product.isLifetime ? Color.green : Color.blue)
                .cornerRadius(12)
            }
            .disabled(proUserManager.purchaseState == .purchasing)
        }
    }

    private func getPeriodText(for product: Product) -> String {
        guard let subscription = product.subscription else { return "" }

        switch subscription.subscriptionPeriod.unit {
        case .day:
            return "\(subscription.subscriptionPeriod.value)日ごと"
        case .week:
            return "\(subscription.subscriptionPeriod.value)週間ごと"
        case .month:
            return "\(subscription.subscriptionPeriod.value)ヶ月ごと"
        case .year:
            return "\(subscription.subscriptionPeriod.value)年ごと"
        @unknown default:
            return ""
        }
    }

    private var restoreButton: some View {
        Button(action: {
            Task {
                await proUserManager.restorePurchases()
            }
        }) {
            HStack {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text("購入を復元")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("以前購入した場合はこちら")
                        .font(.caption2)
                        .opacity(0.8)
                }
                Spacer()
            }
            .padding()
            .background(Color(.systemGray5))
            .foregroundColor(.primary)
            .cornerRadius(12)
        }
    }

    private var noProductsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("商品情報を取得できません")
                .font(.headline)

            Text("ネットワーク接続を確認してください")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("再試行") {
                Task {
                    await proUserManager.loadProducts()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Legal Section
    private var legalSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("購入について")
                    .font(.footnote)
                    .fontWeight(.semibold)

                Text("• サブスクリプションと買い切りライセンスからお選びいただけます")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• サブスクリプションはApple IDに請求され、期間終了の24時間以上前にキャンセルしない限り自動更新されます")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• 買い切りライセンスは一度購入すれば永久に広告なしで使用できます")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• 購入はApple IDに紐付けられ、同じApple IDの端末で利用できます")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("• サブスクリプションは設定アプリ > Apple ID > サブスクリプションから管理・解約できます")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 法的リンク
            HStack(spacing: 16) {
                Link("プライバシーポリシー", destination: URL(string: "https://yok1012.github.io/MuscleBuildingRecorder/")!)
                Link("利用規約", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.footnote)
        }
    }

    private var subscriptionTermsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let monthlyProduct = proUserManager.monthlyProduct {
                VStack(alignment: .leading, spacing: 4) {
                    Text("月額サブスクリプションの詳細")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("月額 \(monthlyProduct.displayPrice)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("いつでもキャンセル可能")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Purchase State Handler
    private func handlePurchaseStateChange(_ state: ProUserManager.PurchaseState) {
        switch state {
        case .purchased:
            alertMessage = "購入が完了しました！広告なしでお楽しみください。"
            showingAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismiss()
            }
        case .failed(let error):
            alertMessage = "購入に失敗しました: \(error)"
            showingAlert = true
        case .cancelled:
            alertMessage = "購入がキャンセルされました"
            showingAlert = true
        default:
            break
        }
    }
}

// MARK: - Feature Row
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

#Preview {
    PurchaseView()
}
