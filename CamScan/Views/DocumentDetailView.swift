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
    @State private var showSignatureEditor = false
    @State private var newSignature: UIImage?
    @State private var signatureRequest: SignatureRequest?
    @State private var annotationRequest: AnnotationRequest?
    @State private var showPasswordPrompt = false
    @State private var exportPassword = ""
    @State private var showNoTablesAlert = false

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
                        startSigning()
                    } label: {
                        Label("Sign", systemImage: "signature")
                    }

                    Button {
                        startDrawing()
                    } label: {
                        Label("Draw & Highlight", systemImage: "pencil.tip.crop.circle")
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

                    Button {
                        if store.isPurchased {
                            exportPassword = ""
                            showPasswordPrompt = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("Export PDF with Password", systemImage: "lock.doc")
                    }
                    .disabled(isExporting)

                    Button {
                        exportTables()
                    } label: {
                        Label("Export Tables (CSV)", systemImage: "tablecells")
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
        .alert("Protect PDF", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $exportPassword)
            Button("Cancel", role: .cancel) {}
            Button("Export") {
                exportPDF(password: exportPassword)
            }
            .disabled(exportPassword.isEmpty)
        } message: {
            Text("The PDF will ask for this password when opened.")
        }
        .alert("No tables found", isPresented: $showNoTablesAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't find a table on these pages.")
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
        .sheet(isPresented: $showSignatureEditor, onDismiss: {
            // Place the signature right after it's first drawn.
            if let signature = newSignature {
                newSignature = nil
                presentSignaturePlacement(signature)
            }
        }) {
            SignatureEditorView { newSignature = $0 }
        }
        .fullScreenCover(item: $signatureRequest) { request in
            SignaturePlacementView(page: request.page, signature: request.signature) { rect in
                addSignature(request.signature, at: rect, to: request.pageID)
            }
        }
        .fullScreenCover(item: $annotationRequest) { request in
            AnnotateView(page: request.background, existing: request.existing) { overlay in
                setDrawing(overlay, on: request.pageID)
            }
        }
        .onChange(of: document.pages.count) {
            selectedPageIndex = min(selectedPageIndex, max(0, document.pages.count - 1))
        }
        .onChange(of: selectedPageIndex) {
            // Show cached OCR if available
            recognizedText = sortedPages[safe: selectedPageIndex]?.recognizedText
        }
    }

    // MARK: - Signature & drawing (Pro)

    private func startSigning() {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        if let drawing = SignatureStore.load(), let signature = SignatureStore.image(from: drawing) {
            presentSignaturePlacement(signature)
        } else {
            showSignatureEditor = true
        }
    }

    private func presentSignaturePlacement(_ signature: UIImage) {
        guard let page = sortedPages[safe: selectedPageIndex], let image = page.image else { return }
        signatureRequest = SignatureRequest(pageID: page.id, page: image, signature: signature)
    }

    private func addSignature(_ signature: UIImage, at rect: CGRect, to pageID: UUID) {
        guard let page = document.pages.first(where: { $0.id == pageID }),
              let data = signature.pngData() else { return }
        var edit = page.edit
        edit.overlays.append(PageOverlay(kind: .signature, imageData: data, rect: rect))
        rerender(page, with: edit)
    }

    /// Shows the page without its drawing, so the existing strokes can be edited in place.
    private func startDrawing() {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        guard let page = sortedPages[safe: selectedPageIndex], let source = page.sourceImage else { return }
        var edit = page.edit
        let existing = edit.drawing
        edit.setDrawing(nil)
        let pageID = page.id

        Task {
            let background = await Task.detached(priority: .userInitiated) {
                ImageFilterService.render(source, edit: edit)
            }.value
            annotationRequest = AnnotationRequest(pageID: pageID, background: background, existing: existing)
        }
    }

    private func setDrawing(_ overlay: PageOverlay?, on pageID: UUID) {
        guard let page = document.pages.first(where: { $0.id == pageID }) else { return }
        var edit = page.edit
        edit.setDrawing(overlay)
        rerender(page, with: edit)
    }

    private func rerender(_ page: ScannedPage, with edit: PageEdit) {
        guard let source = page.sourceImage else { return }
        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                ImageFilterService.render(source, edit: edit)
            }.value
            page.apply(edit: edit, rendered: rendered)
            recognizedText = nil
        }
    }

    // MARK: - OCR

    private func recognizeCurrentPage() {
        guard let page = sortedPages[safe: selectedPageIndex] else { return }

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

    /// Exports a searchable PDF: pages not recognized yet are run through OCR first.
    private func exportPDF(password: String? = nil) {
        isExporting = true
        let pages = sortedPages

        Task {
            var contents: [PDFPageContent] = []
            for page in pages {
                guard let image = page.image else { continue }
                var lines = page.textLines
                if lines == nil {
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
                if let password {
                    return PDFService.encrypt(data, password: password, to: url) ? url : nil
                }
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

    /// Finds tables on every page and shares them as one CSV (Pro).
    private func exportTables() {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        isExporting = true
        let pagesData = sortedPages.map(\.imageData)
        let fileName = PDFService.fileName(for: document.title, extension: "csv")

        Task {
            var tables: [[[String]]] = []
            for data in pagesData {
                if let found = try? await TableExportService.tables(in: data) {
                    tables += found
                }
            }

            isExporting = false
            guard !tables.isEmpty else {
                showNoTablesAlert = true
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try TableExportService.csv(tables).write(to: url, atomically: true, encoding: .utf8)
                pdfURL = url
                showShareSheet = true
            } catch {
                print("Failed to write CSV: \(error)")
            }
        }
    }
}

struct SignatureRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let page: UIImage
    let signature: UIImage
}

struct AnnotationRequest: Identifiable {
    let id = UUID()
    let pageID: UUID
    let background: UIImage
    let existing: PageOverlay?
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
