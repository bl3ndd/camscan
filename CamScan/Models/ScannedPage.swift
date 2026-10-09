import Foundation
import SwiftData
import UIKit

@Model
final class ScannedPage {
    var id: UUID
    var index: Int
    var imageData: Data
    var recognizedText: String?

    var document: ScannedDocument?

    init(index: Int, image: UIImage) {
        self.id = UUID()
        self.index = index
        self.imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        self.recognizedText = nil
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }
}
