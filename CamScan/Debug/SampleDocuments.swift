#if DEBUG
import UIKit
import CoreImage
import SwiftData

/// Synthetic documents for UI-test screenshots and visual filter checks in CI,
/// where there is no camera and no photo library.
nonisolated enum SampleDocuments {
    /// A4-proportioned white page with a title, text lines and a small table.
    static func page(title: String, lines: [String], table: [[String]] = []) -> UIImage {
        let size = CGSize(width: 1240, height: 1754)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            (title as NSString).draw(at: CGPoint(x: 100, y: 120), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 56),
                .foregroundColor: UIColor.black,
            ])
            let body: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34),
                .foregroundColor: UIColor(white: 0.15, alpha: 1),
            ]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 100, y: 260 + CGFloat(index) * 60), withAttributes: body)
            }

            guard let columns = table.first?.count, columns > 0 else { return }
            let top = 260 + CGFloat(lines.count) * 60 + 60
            let rowHeight: CGFloat = 70
            let columnWidth = (size.width - 200) / CGFloat(columns)
            let cg = context.cgContext
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(3)
            for row in 0...table.count {
                let y = top + CGFloat(row) * rowHeight
                cg.move(to: CGPoint(x: 100, y: y))
                cg.addLine(to: CGPoint(x: size.width - 100, y: y))
            }
            for column in 0...columns {
                let x = 100 + CGFloat(column) * columnWidth
                cg.move(to: CGPoint(x: x, y: top))
                cg.addLine(to: CGPoint(x: x, y: top + CGFloat(table.count) * rowHeight))
            }
            cg.strokePath()
            for (row, cells) in table.enumerated() {
                for (column, cell) in cells.enumerated() {
                    (cell as NSString).draw(
                        at: CGPoint(x: 100 + CGFloat(column) * columnWidth + 16, y: top + CGFloat(row) * rowHeight + 14),
                        withAttributes: body
                    )
                }
            }
        }
    }

    /// The page "photographed": tilted on a dark desk, with uneven light falling across it.
    static func photo(of page: UIImage) -> UIImage {
        guard let cgImage = page.cgImage else { return page }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let canvas = CGRect(x: 0, y: 0, width: width * 1.5, height: height * 1.35)

        // Core Image has a bottom-left origin.
        let tilted = CIImage(cgImage: cgImage).applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: width * 0.24, y: canvas.height - height * 0.10),
            "inputTopRight": CIVector(x: width * 1.30, y: canvas.height - height * 0.16),
            "inputBottomRight": CIVector(x: width * 1.36, y: height * 0.12),
            "inputBottomLeft": CIVector(x: width * 0.12, y: height * 0.08),
        ])
        let desk = CIImage(color: CIColor(red: 0.22, green: 0.17, blue: 0.13)).cropped(to: canvas)
        let scene = tilted.composited(over: desk)

        // Light from the top right, shadow towards the bottom left.
        let light = CIImage.empty().applyingFilter("CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: canvas.width, y: canvas.height),
            "inputPoint1": CIVector(x: 0, y: 0),
            "inputColor0": CIColor(red: 1, green: 0.98, blue: 0.94),
            "inputColor1": CIColor(red: 0.45, green: 0.43, blue: 0.40),
        ]).cropped(to: canvas)
        let lit = light.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: scene])

        let context = CIContext()
        guard let output = context.createCGImage(lit, from: canvas) else { return page }
        return UIImage(cgImage: output)
    }

    static let invoice = page(
        title: "Счёт № 42 от 09.10.2026",
        lines: ["Поставщик: ООО «Ромашка»", "Покупатель: ИП Иванов И. И.", "Оплатить до 20.10.2026"],
        table: [["Товар", "Кол-во", "Сумма"], ["Бумага A4", "10", "3 500 ₽"], ["Картридж", "2", "7 800 ₽"], ["Итого", "", "11 300 ₽"]]
    )

    static let contract = page(
        title: "Договор аренды",
        lines: ["г. Москва, 1 октября 2026 г.", "1. Предмет договора", "Арендодатель передаёт, а Арендатор", "принимает во временное пользование", "квартиру по адресу: ул. Ленина, 1."]
    )

    static let receipt = page(
        title: "Кассовый чек",
        lines: ["Кофе латте — 290 ₽", "Круассан — 180 ₽", "Итого: 470 ₽", "Спасибо за покупку!"]
    )
}

/// Launch with `-uiTestSeed` to start from an in-memory store filled with sample documents.
enum UITestSeed {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestSeed")
    }

    @MainActor
    static func seed(_ context: ModelContext) {
        let documents: [(String, [UIImage])] = [
            ("Договор аренды", [SampleDocuments.contract, SampleDocuments.receipt]),
            ("Кассовый чек", [SampleDocuments.receipt]),
            ("Счёт за сентябрь", [SampleDocuments.invoice]),
        ]
        for (offset, (title, pages)) in documents.enumerated() {
            let document = ScannedDocument(title: title)
            // Newest last in the array, so the invoice is on top of the list.
            document.createdAt = Date().addingTimeInterval(Double(offset - documents.count) * 3600)
            for (index, page) in pages.enumerated() {
                let photo = SampleDocuments.photo(of: page)
                if let data = photo.jpegData(compressionQuality: 0.9), let processed = ImportService.process(data) {
                    document.pages.append(ScannedPage(index: index, processed: processed))
                } else {
                    document.pages.append(ScannedPage(index: index, image: page))
                }
            }
            context.insert(document)
        }
    }
}
#endif
