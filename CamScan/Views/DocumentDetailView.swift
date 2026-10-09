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
    @State private var showEditor = false
    @State private var isExporting = false
    @State private var showPages = false
    @State private var showPaywall = false
    @AppStorage("pdfPageSize") private var pageSize: PDFPageSize = .localeDefault

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

            if isExporting {
                ProgressView("Preparing PDF...")
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
                        showEditor = true
                    } label: {
                        Label("Edit Page", systemImage: "crop")
                    }

                    Button {
                        showPages = true
                    } label: {
                        Label("Manage Pages", systemImage: "rectangle.stack")
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
                    .disabled(isExporting)

                    Picker(selection: $pageSize) {
                        ForEach(PDFPageSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    } label: {
                        Label("Page Size", systemImage: "doc.richtext")
                    }
                    .pickerStyle(.menu)

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
        .fullScreenCover(isPresented: $showEditor) {
            if let page = sortedPages[safe: selectedPageIndex],
               let source = page.sourceImage {
                PageEditorView(source: source, edit: page.edit) { edit, rendered in
                    page.apply(edit: edit, rendered: rendered)
                    recognizedText = nil
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
        .sheet(isPresented: $showPages) {
            PagesView(document: document, store: store)
        }
        .onChange(of: document.pages.count) {
            selectedPageIndex = min(selectedPageIndex, max(0, document.pages.count - 1))
        }
        .onChange(of: selectedPageIndex) {
            // Show cached OCR if available
            recognizedText = sortedPages[safe: selectedPageIndex]?.recognizedText
        }
    }

    private func recognizeCurrentPage() {
        guard let page = sortedPages[safe: selectedPageIndex] else { return }

        if !store.isPurchased {
            showPaywall = true
            return
        }

        isRecognizing = true
        recognizedText = nil

        Task {
            do {
                page.setRecognized(try await recognizeLines(on: page))
                recognizedText = page.recognizedText
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
                do {
                    page.setRecognized(try await recognizeLines(on: page))
                    allText.append("--- Page \(page.index + 1) ---\n\(page.recognizedText ?? "")")
                } catch {
                    allText.append("--- Page \(page.index + 1) ---\nFailed: \(error.localizedDescription)")
                }
            }

            recognizedText = allText.joined(separator: "\n\n")
            isRecognizing = false
        }
    }

    /// Runs OCR off the main actor.
    private func recognizeLines(on page: ScannedPage) async throws -> [TextLine] {
        guard let image = page.image else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try OCRService.recognizeLines(in: image)
        }.value
    }

    /// Exports a searchable PDF: pages not recognized yet are run through OCR first (Pro).
    private func exportPDF() {
        isExporting = true
        let pages = sortedPages

        Task {
            var contents: [PDFPageContent] = []
            for page in pages {
                guard let image = page.image else { continue }
                var lines = page.textLines
                if lines == nil, store.isPurchased {
                    lines = try? await recognizeLines(on: page)
                    if let lines { page.setRecognized(lines) }
                }
                contents.append(PDFPageContent(image: image, lines: lines ?? []))
            }

            let pageContents = contents
            let pageSize = pageSize
            let fileName = PDFService.fileName(for: document.title)
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                let data = PDFService.generatePDF(from: pageContents, pageSize: pageSize)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try data.write(to: url)
                    return url
                } catch {
                    print("Failed to write PDF: \(error)")
                    return nil
                }
            }.value

            isExporting = false
            if let url {
                pdfURL = url
                showShareSheet = true
            }
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
