import SwiftUI
import SwiftData
import PhotosUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedDocument.createdAt, order: .reverse) private var documents: [ScannedDocument]

    @StateObject private var store = StoreService()
    @State private var showScanner = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false

    private var filteredDocuments: [ScannedDocument] {
        if searchText.isEmpty { return documents }
        return documents.filter { doc in
            doc.title.localizedCaseInsensitiveContains(searchText) ||
            doc.pages.contains { $0.recognizedText?.localizedCaseInsensitiveContains(searchText) == true }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    emptyState
                } else {
                    documentList
                }
            }
            .navigationTitle("CamScan")
            .searchable(text: $searchText, prompt: "Search documents & text")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            startScan()
                        } label: {
                            Label("Scan with Camera", systemImage: "camera")
                        }
                        Button {
                            startImport()
                        } label: {
                            Label("Import from Photos", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "doc.viewfinder")
                            .font(.title2)
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.isPurchased {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Pro")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView(
                    onScan: { images in
                        saveDocument(images: images)
                        ScanLimitService.recordScan()
                        showScanner = false
                    },
                    onCancel: {
                        showScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 30, matching: .images)
            .onChange(of: photoItems) { importPhotos() }
            .overlay {
                if isImporting {
                    ProgressView("Processing photos…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .environmentObject(store)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Documents", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Tap the scan button to scan your first document")
        } actions: {
            Button("Scan Document") {
                startScan()
            }
            .buttonStyle(.borderedProminent)

            Button("Import from Photos") {
                startImport()
            }
        }
    }

    private var documentList: some View {
        List {
            if !store.isPurchased {
                Section {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text("\(ScanLimitService.remainingScans) free scans left today")
                            .font(.subheadline)
                        Spacer()
                        Button("Go Pro") { showPaywall = true }
                            .font(.subheadline.bold())
                    }
                }
            }

            Section {
                ForEach(filteredDocuments) { document in
                    NavigationLink(value: document) {
                        DocumentRow(document: document)
                    }
                }
                .onDelete(perform: deleteDocuments)
            }
        }
        .navigationDestination(for: ScannedDocument.self) { document in
            DocumentDetailView(document: document)
        }
    }

    private func startScan() {
        if ScanLimitService.canScan() {
            showScanner = true
        } else {
            showPaywall = true
        }
    }

    private func startImport() {
        if ScanLimitService.canScan() {
            showPhotoPicker = true
        } else {
            showPaywall = true
        }
    }

    /// Finds the document on each photo, crops it and evens out the lighting, off the main actor.
    private func importPhotos() {
        let items = photoItems
        guard !items.isEmpty else { return }
        photoItems = []
        isImporting = true

        Task {
            var processed: [ProcessedPage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let page = await Task.detached(priority: .userInitiated) {
                    ImportService.process(data)
                }.value
                if let page {
                    processed.append(page)
                }
            }

            if !processed.isEmpty {
                let pages = processed.enumerated().map { ScannedPage(index: $0.offset, processed: $0.element) }
                saveDocument(pages: pages)
                ScanLimitService.recordScan()
            }
            isImporting = false
        }
    }

    private func saveDocument(images: [UIImage]) {
        saveDocument(pages: images.enumerated().map { ScannedPage(index: $0.offset, image: $0.element) })
    }

    private func saveDocument(pages: [ScannedPage]) {
        let document = ScannedDocument(title: "Scan \(formattedDate())")
        document.pages.append(contentsOf: pages)
        modelContext.insert(document)
    }

    private func deleteDocuments(at offsets: IndexSet) {
        let docs = filteredDocuments
        for index in offsets {
            modelContext.delete(docs[index])
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

struct DocumentRow: View {
    let document: ScannedDocument

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = document.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 65)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 50, height: 65)
                    .overlay {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(document.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
