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
                List {
                    ForEach(documents) { document in
                        NavigationLink(value: document) {
                            DocumentRow(document: document)
                        }
                        .contextMenu {
                            Button {
                                document.folder = nil
                            } label: {
                                Label("Remove from Folder", systemImage: "folder.badge.minus")
                            }
                        }
                    }
                    .onDelete { offsets in
                        let docs = documents
                        for index in offsets {
                            modelContext.delete(docs[index])
                        }
                    }
                }
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
