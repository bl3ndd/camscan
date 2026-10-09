import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var appLock: AppLock
    @Environment(\.dismiss) private var dismiss

    @AppStorage("pdfPageSize") private var pageSize: PDFPageSize = .localeDefault
    @AppStorage("pdfQuality") private var quality: PDFQuality = .medium
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var showPaywall = false
    @State private var showSignature = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.isPurchased {
                        Label("CamScan Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            Label("Get CamScan Pro", systemImage: "sparkles")
                        }
                        Button("Restore Purchase") {
                            Task { await store.restorePurchases() }
                        }
                    }
                }

                Section("Security") {
                    Toggle(isOn: Binding(
                        get: { lockEnabled && store.isPurchased },
                        set: { setLock($0) }
                    )) {
                        Label("Face ID Lock", systemImage: "faceid")
                    }
                }

                Section("Signature") {
                    Button {
                        if store.isPurchased {
                            showSignature = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("My Signature", systemImage: "signature")
                    }
                }

                Section("PDF") {
                    Picker("Page Size", selection: $pageSize) {
                        ForEach(PDFPageSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Picker("PDF Quality", selection: $quality) {
                        ForEach(PDFQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                }

                Section {
                    Label("Everything is processed on your device. No ads, no tracking, no data collected.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        LabeledContent("Version", value: version)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
            .sheet(isPresented: $showSignature) {
                SignatureEditorView()
            }
        }
    }

    private func setLock(_ enabled: Bool) {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        Task {
            if await appLock.setEnabled(enabled) {
                lockEnabled = enabled
            }
        }
    }
}
