import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Deleting a folder keeps its documents; they move back to the main list.
    @Relationship(deleteRule: .nullify, inverse: \ScannedDocument.folder) var documents: [ScannedDocument]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.documents = []
    }
}
