import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedDocument.createdAt, order: .reverse) private var documents: [ScannedDocument]

    @EnvironmentObject private var store: StoreService
    @State private var showSettings = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showScanner = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<PersistentIdentifier>()

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
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import from Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "doc.viewfinder")
                            .font(.title2)
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !documents.isEmpty {
                        Button(editMode.isEditing ? LocalizedStringKey("Done") : LocalizedStringKey("Select")) {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                                selection.removeAll()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editMode.isEditing {
                        Button("Merge \(selection.count) Documents") {
                            mergeSelected()
                        }
                        .disabled(selection.count < 2)
                    }
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: Binding(
                get: { !hasSeenOnboarding },
                set: { hasSeenOnboarding = !$0 }
            )) {
                OnboardingView()
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 30, matching: .images)
            .onChange(of: photoItems) { importPhotos() }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    importFiles(urls)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
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

            Button("Import from Files") {
                showFileImporter = true
            }
        }
    }

    private var documentList: some View {
        List(selection: $selection) {
            Section {
                ForEach(filteredDocuments) { document in
                    NavigationLink(value: document) {
                        DocumentRow(document: document)
                    }
                    .tag(document.persistentModelID)
                }
                .onDelete(perform: deleteDocuments)
            }
        }
        .environment(\.editMode, $editMode)
        .navigationDestination(for: ScannedDocument.self) { document in
            DocumentDetailView(document: document)
        }
    }

    private func startScan() {
        showScanner = true
    }

    private func startImport() {
        showPhotoPicker = true
    }

    /// Imports PDFs page by page and images with automatic cropping, as one document.
    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true

        Task {
            let processed = await Task.detached(priority: .userInitiated) {
                urls.flatMap { ImportService.processFile(at: $0) }
            }.value

            if !processed.isEmpty {
                let pages = processed.enumerated().map { ScannedPage(index: $0.offset, processed: $0.element) }
                let title = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : nil
                saveDocument(pages: pages, title: title)
            }
            isImporting = false
        }
    }

    /// Combines the selected documents, oldest first, into a new document (Pro). Originals are kept.
    private func mergeSelected() {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        let selected = documents
            .filter { selection.contains($0.persistentModelID) }
            .sorted { $0.createdAt < $1.createdAt }
        guard selected.count >= 2 else { return }

        var pages: [ScannedPage] = []
        for document in selected {
            for page in document.pages.sorted(by: { $0.index < $1.index }) {
                pages.append(ScannedPage(index: pages.count, copying: page))
            }
        }
        saveDocument(pages: pages, title: String(localized: "Merged \(formattedDate())"))

        withAnimation {
            selection.removeAll()
            editMode = .inactive
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
            }
            isImporting = false
        }
    }

    private func saveDocument(images: [UIImage]) {
        saveDocument(pages: images.enumerated().map { ScannedPage(index: $0.offset, image: $0.element) })
    }

    private func saveDocument(pages: [ScannedPage], title: String? = nil) {
        let document = ScannedDocument(title: title ?? String(localized: "Scan \(formattedDate())"))
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

                Text("\(document.pageCount) pages")
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
