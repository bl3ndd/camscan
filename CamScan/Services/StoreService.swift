import StoreKit
import Combine

@MainActor
final class StoreService: ObservableObject {
    static let proProductID = "com.camscan.pro"

    @Published var proProduct: Product?
    @Published var isPurchased = false

    init() {
        isPurchased = ScanLimitService.isPro

        Task {
            await loadProduct()
            await checkEntitlement()
            listenForTransactions()
        }
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase() async -> Bool {
        guard let product = proProduct else { return false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                ScanLimitService.unlockPro()
                isPurchased = true
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            print("Purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }

    // MARK: - Private

    private func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductID {
                ScanLimitService.unlockPro()
                isPurchased = true
                return
            }
        }
    }

    private func listenForTransactions() {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == Self.proProductID {
                        await MainActor.run {
                            ScanLimitService.unlockPro()
                            self.isPurchased = true
                        }
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
