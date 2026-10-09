import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedDocument.createdAt, order: .reverse) private var documents: [ScannedDocument]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @State private var showNewFolder = false
    @State private var newFolderName = ""

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
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()

    private var filteredDocuments: [ScannedDocument] {
        // Search looks inside folders too; otherwise the main list shows unfiled documents.
        if searchText.isEmpty { return documents.filter { $0.folder == nil } }
        return documents.filter { doc in
            doc.title.localizedCaseInsensitiveContains(searchText) ||
            doc.pages.contains { $0.recognizedText?.localizedCaseInsensitiveContains(searchText) == true }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty && folders.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Documents")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search documents & text")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationDestination(for: ScannedDocument.self) { document in
                DocumentDetailView(document: document)
            }
            .navigationDestination(for: Folder.self) { folder in
                FolderView(folder: folder)
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
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        modelContext.insert(Folder(name: name))
                    }
                }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }

        if !store.isPurchased {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPaywall = true
                } label: {
                    Text("Pro")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.brand, in: Capsule())
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("proButton")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Done") {
                    withAnimation {
                        isSelecting = false
                        selection.removeAll()
                    }
                }
                .fontWeight(.semibold)
            } else {
                Menu {
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
                    Divider()
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    if documents.count > 1 {
                        Button {
                            withAnimation {
                                selection.removeAll()
                                isSelecting = true
                            }
                        } label: {
                            Label("Select to Merge", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                .disabled(isImporting)
            }
        }
    }

    /// The scan button is the app's main action, so it is always one tap away at the bottom.
    @ViewBuilder
    private var bottomBar: some View {
        if isSelecting {
            Button {
                mergeSelected()
            } label: {
                Text("Merge \(selection.count) Documents")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.count < 2)
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            Button {
                startScan()
            } label: {
                Label("Scan", systemImage: "camera.fill")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(Color.brand, in: Capsule())
                    .shadow(color: Color.brand.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanButton")
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background {
                // Content scrolling under the button fades out instead of clashing with it.
                LinearGradient(
                    colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No documents yet", systemImage: "doc.viewfinder")
        } description: {
            Text("Scan a document with the camera, or import a photo or PDF.")
        } actions: {
            HStack {
                Button {
                    startImport()
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchText.isEmpty && !folders.isEmpty && !isSelecting {
                    foldersRow
                }

                if filteredDocuments.isEmpty {
                    Text(searchText.isEmpty ? "Folders hold the rest of your documents." : "Nothing found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredDocuments) { document in
                            card(for: document)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var foldersRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            FolderChip(folder: folder)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(folder)
                            } label: {
                                Label("Delete Folder", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(for document: ScannedDocument) -> some View {
        if isSelecting {
            let isSelected = selection.contains(document.persistentModelID)
            Button {
                if isSelected {
                    selection.remove(document.persistentModelID)
                } else {
                    selection.insert(document.persistentModelID)
                }
            } label: {
                DocumentCard(document: document, selection: isSelected)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: document) {
                DocumentCard(document: document, selection: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("documentCard")
            .contextMenu {
                if !folders.isEmpty {
                    Menu {
                        ForEach(folders) { folder in
                            Button(folder.name) { document.folder = folder }
                        }
                        if document.folder != nil {
                            Divider()
                            Button("Remove from Folder") { document.folder = nil }
                        }
                    } label: {
                        Label("Move to Folder", systemImage: "folder")
                    }
                }
                Button(role: .destructive) {
                    modelContext.delete(document)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
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
            isSelecting = false
            selection.removeAll()
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

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

/// A document as a page preview with its title, like a sheet of paper on a desk.
struct DocumentCard: View {
    let document: ScannedDocument
    /// `nil` outside of selection mode.
    var selection: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(.secondarySystemGroupedBackground)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let thumbnail = document.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selection == true ? Color.brand : Color.primary.opacity(0.08), lineWidth: selection == true ? 3 : 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                .overlay(alignment: .bottomTrailing) {
                    if document.pageCount > 1 {
                        Label("\(document.pageCount)", systemImage: "doc.on.doc")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let selection {
                        Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selection ? Color.brand : .white)
                            .shadow(radius: 2)
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                (Text("\(document.pageCount) pages") + Text(" · ") + Text(document.createdAt, format: .dateTime.day().month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct FolderChip: View {
    let folder: Folder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(folder.documents.count) documents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
