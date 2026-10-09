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

nonisolated struct PDFPageContent: Sendable {
    let image: UIImage
    let lines: [TextLine]
}

nonisolated enum PDFService {
    /// A cropped sheet of paper should fill its page. Aspect mismatches up to this much
    /// come from perspective error, so the scan is stretched to the page instead of letterboxed.
    static let stretchTolerance: CGFloat = 0.08

    static func generatePDF(from images: [UIImage], pageSize: PDFPageSize) -> Data {
        generatePDF(from: images.map { PDFPageContent(image: $0, lines: []) }, pageSize: pageSize)
    }

    /// Each page is the scan with an invisible text layer on top, so the PDF can be searched and copied from.
    static func generatePDF(from pages: [PDFPageContent], pageSize: PDFPageSize) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect(for: CGSize(width: 1, height: 1), pageSize: .a4))

        return renderer.pdfData { context in
            for content in pages {
                let page = pageRect(for: content.image.size, pageSize: pageSize)
                context.beginPage(withBounds: page, pageInfo: [:])
                let imageRect = drawRect(for: content.image.size, in: page)
                content.image.draw(in: imageRect)
                drawTextLayer(content.lines, in: imageRect, context: context.cgContext)
            }
        }
    }

    private static func drawTextLayer(_ lines: [TextLine], in imageRect: CGRect, context: CGContext) {
        guard !lines.isEmpty else { return }
        context.saveGState()
        context.setTextDrawingMode(.invisible)

        for line in lines where !line.text.isEmpty {
            let rect = CGRect(
                x: imageRect.minX + line.box.minX * imageRect.width,
                y: imageRect.minY + line.box.minY * imageRect.height,
                width: line.box.width * imageRect.width,
                height: line.box.height * imageRect.height
            )
            guard rect.width > 1, rect.height > 1 else { continue }

            let font = UIFont.systemFont(ofSize: rect.height * 0.85)
            let text = NSAttributedString(string: line.text, attributes: [
                .font: font,
                .foregroundColor: UIColor.clear,
            ])
            let textWidth = text.size().width
            guard textWidth > 0 else { continue }

            // Stretch horizontally so selection highlights match the words on the scan.
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / textWidth, y: 1)
            text.draw(at: .zero)
            context.restoreGState()
        }
        context.restoreGState()
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

    /// Re-saves the PDF so it can only be opened with `password`.
    static func encrypt(_ data: Data, password: String, to url: URL) -> Bool {
        guard let document = PDFDocument(data: data) else { return false }
        return document.write(to: url, withOptions: [
            .userPasswordOption: password,
            .ownerPasswordOption: password,
        ])
    }

    /// Characters that can't appear in a file name are replaced, so titles like "Bills 09/2026" export fine.
    static func fileName(for title: String, extension fileExtension: String = "pdf") -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Scan" : cleaned) + "." + fileExtension
    }
}
