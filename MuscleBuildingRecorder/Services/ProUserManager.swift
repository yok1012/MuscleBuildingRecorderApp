//
//  ProUserManager.swift
//  MuscleBuildingRecorder
//
//  StoreKit 2を使用したPro課金管理
//

import Foundation
import StoreKit
import Combine

@MainActor
final class ProUserManager: NSObject, ObservableObject {
    static let shared = ProUserManager()

    // MARK: - Product IDs
    // App Store Connectで設定するProduct ID
    // 月額サブスクリプション（Auto-Renewable Subscription）
    private let monthlySubscriptionID = "com.yokAppDev.MuscleBuildingRecorder.pro.month"
    // 永久ライセンス（Non-Consumable）
    private let lifetimeID = "com.yokAppDev.MuscleBuildingRecorder.pro.lifetime"

    // すべての商品ID
    private var allProductIDs: Set<String> {
        [monthlySubscriptionID, lifetimeID]
    }

    // MARK: - Published Properties
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published private(set) var isPro: Bool = false {
        didSet {
            if oldValue != isPro {
                // Pro状態変更を通知
                NotificationCenter.default.post(
                    name: NSNotification.Name("ProStatusChanged"),
                    object: nil,
                    userInfo: ["isPro": isPro]
                )
                // App Group UserDefaultsに保存（Watch/Widget用）
                saveToAppGroup()
            }
        }
    }
    @Published var purchaseState: PurchaseState = .notStarted
    @Published var isLoadingComplete: Bool = false

    // MARK: - Purchase State
    enum PurchaseState: Equatable {
        case notStarted
        case purchasing
        case purchased
        case failed(String)
        case cancelled

        static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted),
                 (.purchasing, .purchasing),
                 (.purchased, .purchased),
                 (.cancelled, .cancelled):
                return true
            case let (.failed(lhsError), .failed(rhsError)):
                return lhsError == rhsError
            default:
                return false
            }
        }
    }

    // MARK: - Private Properties
    private var updateListenerTask: Task<Void, Error>?
    private let appGroupID = "group.yokAppDev.MuscleBuildingRecorder"
    private let proUserKey = "isPurchased"

    // MARK: - Debug Properties
    #if DEBUG
    private var debugSkipStoreKit = false

    func debugResetPurchaseState() async {
        print("🔧 DEBUG: Force resetting purchase state")

        await MainActor.run {
            self.purchasedProductIDs.removeAll()
            self.isPro = false
            self.purchaseState = .notStarted
        }

        // UserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: proUserKey)
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            sharedDefaults.removeObject(forKey: proUserKey)
            sharedDefaults.synchronize()
        }

        print("✅ DEBUG: Purchase state reset complete")
    }

    func debugSetSkipStoreKit(_ skip: Bool) {
        debugSkipStoreKit = skip
        print("🔧 DEBUG: Skip StoreKit = \(skip)")
    }

    func debugSetPro(_ value: Bool) {
        print("🔧 DEBUG: Setting Pro = \(value)")
        isPro = value
    }
    #endif

    // MARK: - Initialization
    override init() {
        super.init()

        // StoreKit 1のオブザーバーを登録（プロモーション購入対応）
        SKPaymentQueue.default().add(self)

        // トランザクション更新リスナーを開始
        updateListenerTask = listenForTransactions()

        // 未完了のトランザクションを処理
        Task {
            await processUnfinishedTransactions()
        }

        // 初期化時に製品を読み込み
        Task {
            await loadProducts()
            await updatePurchasedProducts()

            await MainActor.run {
                self.isLoadingComplete = true
                print("✅ ProUserManager: Loading complete, isPro = \(self.isPro)")
            }
        }
    }

    deinit {
        updateListenerTask?.cancel()
        SKPaymentQueue.default().remove(self)
    }

    // MARK: - Product Loading
    func loadProducts() async {
        do {
            let products = try await Product.products(for: allProductIDs)

            if products.isEmpty {
                print("⚠️ ProUserManager: No products found")
            } else {
                print("✅ ProUserManager: Loaded \(products.count) products")
                for product in products {
                    print("   - \(product.id): \(product.displayPrice)")
                }
            }

            await MainActor.run {
                self.products = products
            }
        } catch {
            print("❌ ProUserManager: Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase
    func purchase(_ product: Product) async {
        print("🛒 Starting purchase for: \(product.id)")

        await MainActor.run {
            purchaseState = .purchasing
        }

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(.verified(transaction)):
                print("✅ Purchase successful: \(transaction.productID)")
                await transaction.finish()
                await updatePurchasedProducts()

                await MainActor.run {
                    purchaseState = .purchased
                }

            case let .success(.unverified(_, error)):
                print("❌ Purchase unverified: \(error)")
                await MainActor.run {
                    purchaseState = .failed("購入の検証に失敗しました")
                }

            case .pending:
                print("⏳ Purchase pending")
                await MainActor.run {
                    purchaseState = .notStarted
                }

            case .userCancelled:
                print("🚫 Purchase cancelled")
                await MainActor.run {
                    purchaseState = .cancelled
                }

            @unknown default:
                await MainActor.run {
                    purchaseState = .notStarted
                }
            }
        } catch {
            print("❌ Purchase error: \(error)")
            await MainActor.run {
                purchaseState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async {
        await MainActor.run {
            purchaseState = .purchasing
        }

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()

            let hasProVersion = await MainActor.run { self.isPro }

            await MainActor.run {
                if hasProVersion {
                    purchaseState = .purchased
                } else {
                    purchaseState = .failed("購入履歴が見つかりませんでした")
                }
            }
        } catch {
            await MainActor.run {
                purchaseState = .failed("復元に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transaction Handling
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await verificationResult in StoreKit.Transaction.updates {
                await self.handle(transactionVerification: verificationResult)
            }
        }
    }

    private func handle(transactionVerification result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            await transaction.finish()
            await updatePurchasedProducts()
        case .unverified(_, let error):
            print("❌ Unverified transaction: \(error)")
        }
    }

    private func updatePurchasedProducts() async {
        #if DEBUG
        if debugSkipStoreKit {
            print("🔧 DEBUG: Skipping StoreKit update")
            return
        }
        #endif

        var purchasedProductIDs: Set<String> = []

        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            switch verificationResult {
            case let .verified(transaction):
                // 取り消されていない有効な購入を確認
                if transaction.revocationDate == nil {
                    if transaction.productType == .autoRenewable {
                        // サブスクリプション：有効期限を確認
                        if let expirationDate = transaction.expirationDate,
                           expirationDate > Date() {
                            purchasedProductIDs.insert(transaction.productID)
                        }
                    } else {
                        // 非消耗型（永久ライセンス）
                        purchasedProductIDs.insert(transaction.productID)
                    }
                }

            case .unverified(_, _):
                continue
            }
        }

        await MainActor.run {
            self.purchasedProductIDs = purchasedProductIDs
            self.isPro = !purchasedProductIDs.isDisjoint(with: allProductIDs)
            print("📦 ProUserManager: Updated - isPro = \(self.isPro), products = \(purchasedProductIDs)")
        }
    }

    private func processUnfinishedTransactions() async {
        for await verificationResult in StoreKit.Transaction.unfinished {
            switch verificationResult {
            case let .verified(transaction):
                await transaction.finish()
                await updatePurchasedProducts()
            case let .unverified(transaction, _):
                await transaction.finish()
            }
        }
    }

    // MARK: - Helper Methods
    func isPurchased(_ productID: String) -> Bool {
        return purchasedProductIDs.contains(productID)
    }

    func getProduct(for productID: String) -> Product? {
        return products.first { $0.id == productID }
    }

    /// 月額サブスクリプション製品を取得
    var monthlyProduct: Product? {
        products.first { $0.id == monthlySubscriptionID }
    }

    /// 永久ライセンス製品を取得
    var lifetimeProduct: Product? {
        products.first { $0.id == lifetimeID }
    }

    // MARK: - Feature Access Control
    /// 広告をスキップできるか
    func canSkipAds() -> Bool {
        return isPro
    }

    /// 購入状態の読み込みが完了するまで待機
    func waitForLoadingComplete() async {
        if isLoadingComplete {
            return
        }

        let maxWait: TimeInterval = 5.0
        let startTime = Date()

        while !isLoadingComplete {
            if Date().timeIntervalSince(startTime) > maxWait {
                print("⚠️ ProUserManager: Loading timeout")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - App Group Persistence
    private func saveToAppGroup() {
        // 標準UserDefaultsに保存
        UserDefaults.standard.set(isPro, forKey: proUserKey)

        // App GroupのUserDefaultsに保存（Watch/Widget用）
        if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
            sharedDefaults.set(isPro, forKey: proUserKey)
            sharedDefaults.synchronize()
        }
    }
}

// MARK: - StoreKit 1 Delegate (プロモーション購入対応)
extension ProUserManager: SKPaymentTransactionObserver {

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        return true
    }

    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased, .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
                Task { @MainActor in
                    await self.updatePurchasedProducts()
                }
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        Task { @MainActor in
            await self.updatePurchasedProducts()
        }
    }
}

// MARK: - Product Extensions
extension Product {
    var isMonthlySubscription: Bool {
        return type == .autoRenewable
    }

    var isLifetime: Bool {
        return type == .nonConsumable
    }
}
