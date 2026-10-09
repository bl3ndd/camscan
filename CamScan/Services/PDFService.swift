import UIKit
import PDFKit

struct PDFService {
    static func generatePDF(from pages: [ScannedPage]) -> Data {
        let sortedPages = pages.sorted { $0.index < $1.index }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))

        return renderer.pdfData { context in
            for page in sortedPages {
                guard let image = page.image else { continue }

                context.beginPage()

                let pageRect = context.pdfContextBounds
                let imageSize = image.size
                let scale = min(pageRect.width / imageSize.width, pageRect.height / imageSize.height)
                let scaledWidth = imageSize.width * scale
                let scaledHeight = imageSize.height * scale
                let x = (pageRect.width - scaledWidth) / 2
                let y = (pageRect.height - scaledHeight) / 2

                image.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
            }
        }
    }
}
