import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: StoreService
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "doc.viewfinder.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("CamScan Pro")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("Sign documents", icon: "signature")
                    featureRow("Draw & highlight on pages", icon: "pencil.tip.crop.circle")
                    featureRow("Password-protected PDFs", icon: "lock.doc")
                    featureRow("Merge & split documents", icon: "doc.on.doc")
                    featureRow("Export tables to CSV", icon: "tablecells")
                    featureRow("Face ID lock", icon: "faceid")
                    featureRow("One-time purchase, Family Sharing", icon: "heart.fill")
                }
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task {
                            isPurchasing = true
                            _ = await store.purchase()
                            isPurchasing = false
                            if store.isPurchased { dismiss() }
                        }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(priceText)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isPurchasing)

                    Button("Restore Purchase") {
                        Task {
                            await store.restorePurchases()
                            if store.isPurchased { dismiss() }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var priceText: String {
        if let product = store.proProduct {
            return "Unlock Pro — \(product.displayPrice)"
        }
        return "Unlock Pro — $4.99"
    }

    private func featureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.blue)
            Text(text)
                .font(.body)
        }
    }
}
