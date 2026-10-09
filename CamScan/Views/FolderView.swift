import SwiftUI
import SwiftData

struct FolderView: View {
    @Bindable var folder: Folder
    @Environment(\.modelContext) private var modelContext
    @State private var showRename = false
    @State private var newName = ""

    private var documents: [ScannedDocument] {
        folder.documents.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView {
                    Label("Empty Folder", systemImage: "folder")
                } description: {
                    Text("Long-press a document and choose Move to Folder.")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 20) {
                        ForEach(documents) { document in
                            NavigationLink(value: document) {
                                DocumentCard(document: document, selection: nil)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    document.folder = nil
                                } label: {
                                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(document)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newName = folder.name
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .alert("Rename Folder", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { folder.name = name }
            }
        }
    }
}
