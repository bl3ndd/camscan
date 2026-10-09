import Foundation
import SwiftData
import UIKit

@Model
final class ScannedDocument {
    var id: UUID
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var pages: [ScannedPage]
    var folder: Folder?

    init(title: String = "Untitled", pages: [ScannedPage] = []) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.pages = pages
    }

    var pageCount: Int { pages.count }

    var thumbnail: UIImage? {
        guard let data = pages.sorted(by: { $0.index < $1.index }).first?.imageData else { return nil }
        return UIImage(data: data)
    }
}
