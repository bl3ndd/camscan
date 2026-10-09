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
    @State private var shareItems: [URL] = []
    @AppStorage("pdfQuality") private var quality: PDFQuality = .medium
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
    @State private var showTextSheet = false

    private var sortedPages: [ScannedPage] {
        document.pages.sorted { $0.index < $1.index }
    }

    var body: some View {
        TabView(selection: $selectedPageIndex) {
            ForEach(Array(sortedPages.enumerated()), id: \.element.id) { index, page in
                if let image = page.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            if sortedPages.count > 1 {
                Text("\(selectedPageIndex + 1) / \(sortedPages.count)")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .overlay {
            if isExporting {
                ProgressView("Preparing…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .sheet(isPresented: $showTextSheet) {
            RecognizedTextView(text: recognizedText, isRecognizing: isRecognizing)
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
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
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

    // MARK: - Actions

    /// The four things people do with a scan, labelled, always at hand.
    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton("Edit", icon: "crop") { showEditor = true }
                .accessibilityIdentifier("editPage")
            actionButton("Sign", icon: "signature") { startSigning() }
                .accessibilityIdentifier("signButton")
            actionButton("Text", icon: "text.viewfinder") { showText() }
                .accessibilityIdentifier("textButton")
            shareMenu
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .frame(height: 26)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var shareMenu: some View {
        Menu {
            Button {
                exportPDF()
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            Button {
                if store.isPurchased {
                    exportPassword = ""
                    showPasswordPrompt = true
                } else {
                    showPaywall = true
                }
            } label: {
                Label("PDF with Password", systemImage: "lock.doc")
            }
            Button {
                exportImages()
            } label: {
                Label("Images (JPEG)", systemImage: "photo.on.rectangle")
            }
            Button {
                exportText()
            } label: {
                Label("Text (TXT)", systemImage: "doc.plaintext")
            }
            Button {
                exportTables()
            } label: {
                Label("Tables (CSV)", systemImage: "tablecells")
            }

            Divider()

            Picker(selection: $pageSize) {
                ForEach(PDFPageSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            } label: {
                Label("Page Size", systemImage: "doc")
            }
            .pickerStyle(.menu)

            Picker(selection: $quality) {
                ForEach(PDFQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            } label: {
                Label("PDF Quality", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .pickerStyle(.menu)
        } label: {
            actionLabel("Share", icon: "square.and.arrow.up")
        }
        .disabled(isExporting)
        .accessibilityIdentifier("shareMenu")
    }

    /// Less frequent actions.
    private var moreMenu: some View {
        Menu {
            Button {
                newTitle = document.title
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                showPages = true
            } label: {
                Label("Pages", systemImage: "rectangle.stack")
            }
            Button {
                startDrawing()
            } label: {
                Label("Draw & Highlight", systemImage: "pencil.tip.crop.circle")
            }
            if sortedPages.count > 1 {
                Button {
                    showTextSheet = true
                    recognizeAllPages()
                } label: {
                    Label("Text from All Pages", systemImage: "doc.text")
                }
                .disabled(isRecognizing)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("documentMenu")
    }

    /// Shows the page's text, recognizing it first if needed.
    private func showText() {
        showTextSheet = true
        if let cached = sortedPages[safe: selectedPageIndex]?.recognizedText {
            recognizedText = cached
        } else {
            recognizeCurrentPage()
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
            let quality = quality
            let fileName = PDFService.fileName(for: document.title)
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                let data = PDFService.generatePDF(from: pageContents, pageSize: pageSize, quality: quality)
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
                shareItems = [url]
                showShareSheet = true
            }
        }
    }

    /// Shares every page as a JPEG: "Title 1.jpg", "Title 2.jpg"...
    private func exportImages() {
        let pagesData = sortedPages.map(\.imageData)
        let baseName = PDFService.fileName(for: document.title, extension: "jpg").dropLast(4)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            shareItems = try pagesData.enumerated().map { index, data in
                let url = folder.appendingPathComponent("\(baseName) \(index + 1).jpg")
                try data.write(to: url)
                return url
            }
            showShareSheet = true
        } catch {
            print("Failed to write images: \(error)")
        }
    }

    /// Recognizes pages that weren't yet and shares all text as one .txt file.
    private func exportText() {
        isExporting = true
        let pages = sortedPages
        let fileName = PDFService.fileName(for: document.title, extension: "txt")

        Task {
            var texts: [String] = []
            for page in pages {
                if page.textLines == nil, let lines = try? await recognizeLines(on: page) {
                    page.setRecognized(lines)
                }
                texts.append(page.recognizedText ?? "")
            }
            isExporting = false

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try texts.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)
                shareItems = [url]
                showShareSheet = true
            } catch {
                print("Failed to write text: \(error)")
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
                shareItems = [url]
                showShareSheet = true
            } catch {
                print("Failed to write CSV: \(error)")
            }
        }
    }
}

/// Recognized text with copy and share.
struct RecognizedTextView: View {
    let text: String?
    let isRecognizing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if isRecognizing {
                    ProgressView("Recognizing text…")
                } else if let text, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ContentUnavailableView("No text found", systemImage: "text.magnifyingglass")
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let text, !text.isEmpty, !isRecognizing {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            UIPasteboard.general.string = text
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        Spacer()
                        ShareLink(item: text)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
