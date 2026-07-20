import Foundation
import StoreKit

@MainActor
final class PremiumManager: ObservableObject {
    static let shared = PremiumManager()

    @Published private(set) var isPremium = false
    @Published private(set) var formattedPrice: String?
    @Published private(set) var purchaseInProgress = false
    @Published private(set) var purchaseMessage: String?

    private var product: Product?
    private var transactionListener: Task<Void, Never>?

    #if DEBUG
    private static let debugPremiumUnlocked = true
    #else
    private static let debugPremiumUnlocked = false
    #endif

    private init() {
        if Self.debugPremiumUnlocked {
            isPremium = true
            return
        }

        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                await self.handle(transactionResult: result)
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    var isPremiumUnlocked: Bool {
        Self.debugPremiumUnlocked || isPremium
    }

    func purchase() async {
        guard !isPremiumUnlocked else { return }

        if product == nil {
            await loadProducts()
        }

        guard let product else {
            purchaseMessage = "Premium product is unavailable."
            return
        }

        purchaseInProgress = true
        purchaseMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .userCancelled:
                purchaseInProgress = false
            case .pending:
                purchaseInProgress = false
                purchaseMessage = "Purchase is pending approval."
            @unknown default:
                purchaseInProgress = false
            }
        } catch {
            purchaseInProgress = false
            purchaseMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard !isPremiumUnlocked else { return }

        purchaseInProgress = true
        purchaseMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseInProgress = false
            if !isPremium {
                purchaseMessage = "No premium purchase found."
            } else {
                purchaseMessage = "Premium unlocked."
            }
        } catch {
            purchaseInProgress = false
            purchaseMessage = "Could not restore purchases."
        }
    }

    func clearPurchaseMessage() {
        purchaseMessage = nil
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [AppInfo.premiumProductId])
            product = products.first
            formattedPrice = product?.displayPrice
        } catch {
            purchaseMessage = "Could not load premium product."
        }
    }

    private func refreshEntitlements() async {
        var owned = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == AppInfo.premiumProductId {
                owned = true
            }
        }

        isPremium = owned
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else {
            purchaseInProgress = false
            return
        }

        if transaction.productID == AppInfo.premiumProductId {
            isPremium = true
            purchaseMessage = "Premium unlocked."
        }

        await transaction.finish()
        purchaseInProgress = false
    }
}
