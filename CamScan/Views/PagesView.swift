import SwiftUI
import SwiftData

/// Reorder, delete and add pages of a document.
struct PagesView: View {
    @Bindable var document: ScannedDocument
    @ObservedObject var store: StoreService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showScanner = false
    @State private var showPaywall = false
    @State private var selection = Set<UUID>()

    private var sortedPages: [ScannedPage] {
        document.pages.sorted { $0.index < $1.index }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(sortedPages) { page in
                    HStack(spacing: 12) {
                        if let image = page.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text("Page \(page.index + 1)")
                    }
                    .tag(page.id)
                }
                .onMove(perform: movePages)
                .onDelete(perform: deletePages)
                .deleteDisabled(document.pages.count <= 1)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Add Pages", systemImage: "plus.viewfinder")
                    }

                    Spacer()

                    Button("Move to New Document") {
                        moveSelectionToNewDocument()
                    }
                    .disabled(selection.isEmpty || selection.count >= document.pages.count)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView(
                    onScan: { images in
                        appendPages(images)
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
        }
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        var pages = sortedPages
        pages.move(fromOffsets: source, toOffset: destination)
        reindex(pages)
    }

    private func deletePages(at offsets: IndexSet) {
        let pages = sortedPages
        let removed = offsets.map { pages[$0] }
        let removedIDs = Set(removed.map(\.id))
        document.pages.removeAll { removedIDs.contains($0.id) }
        for page in removed {
            modelContext.delete(page)
        }
        reindex(sortedPages)
    }

    /// Splits the selected pages off into a new document (Pro).
    private func moveSelectionToNewDocument() {
        guard store.isPurchased else {
            showPaywall = true
            return
        }
        let moving = sortedPages.filter { selection.contains($0.id) }
        guard !moving.isEmpty, moving.count < document.pages.count else { return }

        let newDocument = ScannedDocument(title: String(localized: "\(document.title) (part)"))
        for (index, page) in moving.enumerated() {
            newDocument.pages.append(ScannedPage(index: index, copying: page))
        }
        modelContext.insert(newDocument)

        document.pages.removeAll { selection.contains($0.id) }
        for page in moving {
            modelContext.delete(page)
        }
        reindex(sortedPages)
        selection.removeAll()
    }

    private func appendPages(_ images: [UIImage]) {
        let start = document.pages.count
        for (offset, image) in images.enumerated() {
            document.pages.append(ScannedPage(index: start + offset, image: image))
        }
    }

    private func reindex(_ pages: [ScannedPage]) {
        for (index, page) in pages.enumerated() where page.index != index {
            page.index = index
        }
    }
}
