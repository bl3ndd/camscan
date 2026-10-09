import SwiftUI

struct DocumentDetailView: View {
    @Bindable var document: ScannedDocument
    @EnvironmentObject private var store: StoreService

    @State private var selectedPageIndex = 0
    @State private var showRenameAlert = false
    @State private var newTitle = ""
    @State private var recognizedText: String?
    @State private var isRecognizing = false
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var showFilterSheet = false
    @State private var showPaywall = false

    private var sortedPages: [ScannedPage] {
        document.pages.sorted { $0.index < $1.index }
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedPageIndex) {
                ForEach(Array(sortedPages.enumerated()), id: \.element.id) { index, page in
                    if let image = page.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            if sortedPages.count > 1 {
                Text("Page \(selectedPageIndex + 1) of \(sortedPages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            if isRecognizing {
                ProgressView("Recognizing text...")
                    .padding()
            }

            if let text = recognizedText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding()
                }
                .frame(maxHeight: 200)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        newTitle = document.title
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        showFilterSheet = true
                    } label: {
                        Label("Filters", systemImage: "camera.filters")
                    }

                    Divider()

                    Button {
                        recognizeCurrentPage()
                    } label: {
                        Label("OCR — Current Page", systemImage: "text.viewfinder")
                    }
                    .disabled(isRecognizing)

                    Button {
                        recognizeAllPages()
                    } label: {
                        Label("OCR — All Pages", systemImage: "text.page.fill")
                    }
                    .disabled(isRecognizing)

                    Divider()

                    Button {
                        exportPDF()
                    } label: {
                        Label("Export PDF", systemImage: "arrow.up.doc")
                    }

                    if let text = recognizedText, !text.isEmpty {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Document", isPresented: $showRenameAlert) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                document.title = newTitle
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            if let page = sortedPages[safe: selectedPageIndex],
               let image = page.image {
                PageFilterView(originalImage: image) { filteredImage, _ in
                    page.imageData = filteredImage.jpegData(compressionQuality: 0.8) ?? Data()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(store: store)
        }
        .onChange(of: selectedPageIndex) {
            // Show cached OCR if available
            recognizedText = sortedPages[safe: selectedPageIndex]?.recognizedText
        }
    }

    private func recognizeCurrentPage() {
        guard let page = sortedPages[safe: selectedPageIndex],
              let image = page.image else { return }

        if !store.isPurchased {
            showPaywall = true
            return
        }

        isRecognizing = true
        recognizedText = nil

        Task {
            do {
                let text = try await OCRService.recognizeText(in: image)
                page.recognizedText = text
                recognizedText = text
            } catch {
                recognizedText = "Failed: \(error.localizedDescription)"
            }
            isRecognizing = false
        }
    }

    private func recognizeAllPages() {
        if !store.isPurchased {
            showPaywall = true
            return
        }

        isRecognizing = true
        recognizedText = nil

        Task {
            var allText: [String] = []

            for page in sortedPages {
                guard let image = page.image else { continue }
                do {
                    let text = try await OCRService.recognizeText(in: image)
                    page.recognizedText = text
                    allText.append("--- Page \(page.index + 1) ---\n\(text)")
                } catch {
                    allText.append("--- Page \(page.index + 1) ---\nFailed: \(error.localizedDescription)")
                }
            }

            recognizedText = allText.joined(separator: "\n\n")
            isRecognizing = false
        }
    }

    private func exportPDF() {
        let pdfData = PDFService.generatePDF(from: sortedPages)
        let fileName = "\(document.title).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: tempURL)
            pdfURL = tempURL
            showShareSheet = true
        } catch {
            print("Failed to write PDF: \(error)")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
