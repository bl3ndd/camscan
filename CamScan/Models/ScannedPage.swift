import Foundation
import SwiftData
import UIKit

@Model
final class ScannedPage {
    var id: UUID
    var index: Int
    /// Rendered page (crop and filters applied): what is shown, recognized and exported.
    @Attribute(.externalStorage) var imageData: Data
    /// Untouched source the edits are applied to. `nil` until the page is first edited or when nothing was changed.
    @Attribute(.externalStorage) var originalImageData: Data?
    /// JSON-encoded `PageEdit`.
    var editData: Data?
    var recognizedText: String?

    var document: ScannedDocument?

    init(index: Int, image: UIImage) {
        self.id = UUID()
        self.index = index
        self.imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        self.recognizedText = nil
    }

    init(index: Int, processed: ProcessedPage) {
        self.id = UUID()
        self.index = index
        self.imageData = processed.imageData
        self.originalImageData = processed.originalImageData
        self.editData = try? JSONEncoder().encode(processed.edit)
        self.recognizedText = nil
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }

    var sourceImage: UIImage? {
        UIImage(data: originalImageData ?? imageData)
    }

    var edit: PageEdit {
        editData.flatMap { try? JSONDecoder().decode(PageEdit.self, from: $0) } ?? PageEdit()
    }

    func apply(edit: PageEdit, rendered: UIImage) {
        if originalImageData == nil {
            originalImageData = imageData
        }
        imageData = rendered.jpegData(compressionQuality: 0.8) ?? imageData
        editData = try? JSONEncoder().encode(edit)
        recognizedText = nil
    }
}
