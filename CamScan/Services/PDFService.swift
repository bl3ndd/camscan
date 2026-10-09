import UIKit
import PDFKit

nonisolated enum PDFPageSize: String, CaseIterable, Identifiable, Sendable {
    case a4
    case letter
    case fitImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .fitImage: "Fit to Image"
        }
    }

    /// Portrait size in points; `nil` means the page follows the image.
    var portraitSize: CGSize? {
        switch self {
        case .a4: CGSize(width: 595.2, height: 841.8)
        case .letter: CGSize(width: 612, height: 792)
        case .fitImage: nil
        }
    }

    static var localeDefault: PDFPageSize {
        let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "CL", "CO", "VE"]
        return letterRegions.contains(Locale.current.region?.identifier ?? "") ? .letter : .a4
    }
}

nonisolated enum PDFService {
    /// A cropped sheet of paper should fill its page. Aspect mismatches up to this much
    /// come from perspective error, so the scan is stretched to the page instead of letterboxed.
    static let stretchTolerance: CGFloat = 0.08

    @MainActor
    static func generatePDF(from pages: [ScannedPage], pageSize: PDFPageSize) -> Data {
        let images = pages.sorted { $0.index < $1.index }.compactMap(\.image)
        return generatePDF(from: images, pageSize: pageSize)
    }

    static func generatePDF(from images: [UIImage], pageSize: PDFPageSize) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect(for: CGSize(width: 1, height: 1), pageSize: .a4))

        return renderer.pdfData { context in
            for image in images {
                let page = pageRect(for: image.size, pageSize: pageSize)
                context.beginPage(withBounds: page, pageInfo: [:])
                image.draw(in: drawRect(for: image.size, in: page))
            }
        }
    }

    /// Paper sizes turn landscape for landscape scans. "Fit to Image" keeps the scan's
    /// proportions with the long side of an A4 sheet, so text prints at a familiar size.
    static func pageRect(for imageSize: CGSize, pageSize: PDFPageSize) -> CGRect {
        guard let portrait = pageSize.portraitSize else {
            let longSide: CGFloat = 841.8
            let scale = longSide / max(imageSize.width, imageSize.height, 1)
            return CGRect(
                x: 0, y: 0,
                width: max(1, (imageSize.width * scale).rounded()),
                height: max(1, (imageSize.height * scale).rounded())
            )
        }
        let isLandscape = imageSize.width > imageSize.height
        let size = isLandscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
        return CGRect(origin: .zero, size: size)
    }

    static func drawRect(for imageSize: CGSize, in page: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return page }

        let imageAspect = imageSize.width / imageSize.height
        let pageAspect = page.width / page.height
        if abs(imageAspect / pageAspect - 1) <= stretchTolerance {
            return page
        }

        let scale = min(page.width / imageSize.width, page.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: page.midX - size.width / 2,
            y: page.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Characters that can't appear in a file name are replaced, so titles like "Bills 09/2026" export fine.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Scan" : cleaned) + ".pdf"
    }
}
