import SwiftUI

/// Shown once on first launch: what makes the app different.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "doc.viewfinder.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to CamScan")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 20) {
                row("No ads, no watermarks", "Scan, crop, recognize text and export PDFs for free, without limits.", icon: "nosign")
                row("Private by design", "Everything is processed on your iPhone. Your documents never leave it.", icon: "lock.shield")
                row("No subscriptions", "Pro is a one-time purchase, shared with your family.", icon: "heart")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .interactiveDismissDisabled()
    }

    private func row(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
