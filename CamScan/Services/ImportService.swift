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
    /// Asks both the ML document segmenter and classic rectangle detection and takes the
    /// largest plausible quad: the segmenter is sometimes confidently wrong and returns
    /// only part of the sheet, while a part is always smaller than the whole page.
    static func detectQuad(in image: UIImage) -> Quad? {
        let candidates = detect(in: image)
        let plausible = [candidates.segment, candidates.rectangle]
            .compactMap { $0 }
            .filter { $0.confidence >= 0.3 && area(of: $0) > 0.1 }
        guard let best = plausible.max(by: { area(of: $0) < area(of: $1) }) else { return nil }
        return quad(from: best)
    }

    /// What each detector found, for test failure messages.
    static func diagnostics(for image: UIImage) -> String {
        let candidates = detect(in: image)
        func describe(_ observation: VNRectangleObservation?) -> String {
            guard let observation else { return "none" }
            return String(format: "confidence %.2f, area %.2f", observation.confidence, area(of: observation))
        }
        return "segmentation: \(describe(candidates.segment)); rectangles: \(describe(candidates.rectangle))"
    }

    private static func detect(in image: UIImage) -> (segment: VNRectangleObservation?, rectangle: VNRectangleObservation?) {
        guard let cgImage = image.upright().cgImage else { return (nil, nil) }

        let segmentation = VNDetectDocumentSegmentationRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.3
        rectangles.maximumAspectRatio = 1
        rectangles.minimumSize = 0.25
        rectangles.quadratureTolerance = 30
        rectangles.minimumConfidence = 0.5
        rectangles.maximumObservations = 3

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([segmentation, rectangles])

        let segment = segmentation.results?.first
        let rectangle = rectangles.results?.max { area(of: $0) < area(of: $1) }
        return (segment, rectangle)
    }

    /// Normalized area of the quadrilateral (shoelace formula).
    private static func area(of observation: VNRectangleObservation) -> CGFloat {
        let points = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
        var sum: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Pulls detected corners slightly towards the centre, so no sliver of the desk
    /// survives at the page edge after perspective correction.
    static let edgeInset: CGFloat = 0.006

    private static func quad(from observation: VNRectangleObservation) -> Quad {
        let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
        let center = CGPoint(
            x: corners.map(\.x).reduce(0, +) / 4,
            y: corners.map(\.y).reduce(0, +) / 4
        )
        // Vision has a bottom-left origin.
        func flipped(_ point: CGPoint) -> CGPoint {
            let inset = CGPoint(
                x: point.x + (center.x - point.x) * edgeInset * 2,
                y: point.y + (center.y - point.y) * edgeInset * 2
            )
            return CGPoint(x: inset.x, y: 1 - inset.y)
        }
        return Quad(
            topLeft: flipped(observation.topLeft),
            topRight: flipped(observation.topRight),
            bottomRight: flipped(observation.bottomRight),
            bottomLeft: flipped(observation.bottomLeft)
        )
    }
}
