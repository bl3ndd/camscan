import UIKit
import Vision
import PDFKit

/// A page prepared off the main actor, ready to be stored as a `ScannedPage`.
nonisolated struct ProcessedPage: Sendable {
    let imageData: Data
    /// `nil` when the page was imported as-is, so the original is `imageData` itself.
    let originalImageData: Data?
    let edit: PageEdit
}

nonisolated enum ImportService {
    /// Long side limit for imported photos; plenty for print and keeps storage sane.
    static let maxDimension: CGFloat = 3000

    /// Finds the document on a photo, crops it and evens out the lighting.
    /// Synchronous and slow: call from a detached task.
    static func process(_ data: Data) -> ProcessedPage? {
        guard let image = UIImage(data: data)?.upright(maxDimension: maxDimension) else { return nil }

        let edit = PageEdit(quad: DocumentDetector.detectQuad(in: image) ?? .full, filter: .auto)
        let rendered = ImageFilterService.render(image, edit: edit)

        guard let originalData = image.jpegData(compressionQuality: 0.9),
              let renderedData = rendered.jpegData(compressionQuality: 0.8) else { return nil }
        return ProcessedPage(imageData: renderedData, originalImageData: originalData, edit: edit)
    }
}

nonisolated extension ImportService {
    /// Renders each PDF page to an image. PDFs are already flat, so no crop or filter is applied.
    static func processPDF(at url: URL) -> [ProcessedPage] {
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let longSide = max(bounds.width, bounds.height)
            guard longSide > 0 else { return nil }
            // About 250 dpi for a letter-size page, capped like photos.
            let scale = min(maxDimension / longSide, 3.5)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let data = image.upright().jpegData(compressionQuality: 0.85) else { return nil }
            return ProcessedPage(imageData: data, originalImageData: nil, edit: PageEdit())
        }
    }

    static func processFile(at url: URL) -> [ProcessedPage] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "pdf" {
            return processPDF(at: url)
        }
        guard let data = try? Data(contentsOf: url), let page = process(data) else { return [] }
        return [page]
    }
}

nonisolated enum DocumentDetector {
    /// Corners of the document on an upright image, or `nil` if none was found.
    static func detectQuad(in image: UIImage) -> Quad? {
        guard let cgImage = image.upright().cgImage else { return nil }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              observation.confidence > 0.5 else { return nil }

        // Vision has a bottom-left origin.
        func flipped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: 1 - point.y)
        }
        return Quad(
            topLeft: flipped(observation.topLeft),
            topRight: flipped(observation.topRight),
            bottomRight: flipped(observation.bottomRight),
            bottomLeft: flipped(observation.bottomLeft)
        )
    }
}
