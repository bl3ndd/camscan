//
//  CamScanTests.swift
//  CamScanTests
//
//  Created by Evgeny Varzin on 28.03.2026.
//

import Testing
import Foundation
import UIKit
import PDFKit
@testable import CamScan

struct PDFServiceTests {

    @Test func paperPageTurnsLandscapeForLandscapeScan() {
        let portrait = PDFService.pageRect(for: CGSize(width: 1000, height: 1400), pageSize: .a4)
        #expect(portrait.size == CGSize(width: 595.2, height: 841.8))

        let landscape = PDFService.pageRect(for: CGSize(width: 1400, height: 1000), pageSize: .a4)
        #expect(landscape.size == CGSize(width: 841.8, height: 595.2))
    }

    @Test func fitToImagePageKeepsProportions() {
        let page = PDFService.pageRect(for: CGSize(width: 2000, height: 1000), pageSize: .fitImage)
        #expect(page.width == 842)
        #expect(page.height == 421)
    }

    @Test func nearlyMatchingScanIsStretchedToFillPage() {
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        // 1.38 vs A4's 1.414: perspective error, should fill the sheet.
        let rect = PDFService.drawRect(for: CGSize(width: 1000, height: 1380), in: page)
        #expect(rect == page)
    }

    @Test func differentShapeIsCenteredWithoutDistortion() {
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        let rect = PDFService.drawRect(for: CGSize(width: 500, height: 500), in: page)
        #expect(rect == CGRect(x: 0, y: 100, width: 600, height: 600))
    }

    @Test func pdfHasOnePagePerImage() throws {
        let images = [CGSize(width: 100, height: 140), CGSize(width: 140, height: 100)].map { size in
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }
        let data = PDFService.generatePDF(from: images, pageSize: .letter)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
    }

    @Test func fileNameDropsPathCharacters() {
        #expect(PDFService.fileName(for: "Bills 09/2026") == "Bills 09-2026.pdf")
        #expect(PDFService.fileName(for: "  ") == "Scan.pdf")
    }
}

struct PageEditTests {

    @Test func editSurvivesEncoding() throws {
        var edit = PageEdit()
        edit.quad.setCorner(2, to: CGPoint(x: 0.9, y: 0.8))
        edit.filter = .magicColor
        edit.rotation = 1

        let decoded = try JSONDecoder().decode(PageEdit.self, from: JSONEncoder().encode(edit))
        #expect(decoded == edit)
        #expect(!decoded.quad.isFull)
    }

    @Test func renderAppliesRotation() {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        var edit = PageEdit()
        edit.rotation = 1

        let rendered = ImageFilterService.render(source, edit: edit)
        #expect(rendered.size.width < rendered.size.height)
    }
}

struct SearchablePDFTests {

    @Test func textLayerMakesPDFSearchable() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }
        let lines = [
            TextLine(text: "Invoice 42", box: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.04)),
            TextLine(text: "Счёт за сентябрь", box: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.04)),
        ]

        let data = PDFService.generatePDF(from: [PDFPageContent(image: image, lines: lines)], pageSize: .a4)
        let text = try #require(PDFDocument(data: data)?.string)
        #expect(text.contains("Invoice 42"))
        #expect(text.contains("Счёт за сентябрь"))
    }
}

struct OverlayTests {

    @Test func editsSavedBeforeOverlaysStillLoad() throws {
        let legacy = #"{"quad":{"topLeft":[0.1,0.1],"topRight":[0.9,0.1],"bottomRight":[0.9,0.9],"bottomLeft":[0.1,0.9]},"filter":"Auto","brightness":0,"contrast":1,"rotation":0}"#
        let edit = try JSONDecoder().decode(PageEdit.self, from: Data(legacy.utf8))
        #expect(edit.filter == .auto)
        #expect(!edit.quad.isFull)
        #expect(edit.overlays.isEmpty)
    }

    @Test func overlayIsDrawnOnPage() throws {
        let size = CGSize(width: 100, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let ink = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let overlay = PageOverlay(kind: .signature, imageData: try #require(ink.pngData()), rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))

        let result = ImageFilterService.withOverlays(page, [overlay])
        #expect(brightness(of: result, at: CGPoint(x: 75, y: 75)) < 0.1)
        #expect(brightness(of: result, at: CGPoint(x: 25, y: 25)) > 0.9)
    }

    @Test func drawingIsReplacedNotDuplicated() {
        var edit = PageEdit()
        edit.setDrawing(PageOverlay(kind: .drawing, imageData: Data([1]), rect: .zero))
        edit.setDrawing(PageOverlay(kind: .drawing, imageData: Data([2]), rect: .zero))
        #expect(edit.overlays.count == 1)
        #expect(edit.drawing?.imageData == Data([2]))
        edit.setDrawing(nil)
        #expect(edit.overlays.isEmpty)
    }

    private func brightness(of image: UIImage, at point: CGPoint) -> CGFloat {
        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: CGRect(origin: point, size: CGSize(width: 1, height: 1))) else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGFloat(pixel[0]) / 255
    }
}

struct ExportTests {

    @Test func csvEscapesSpecialCharacters() {
        let csv = TableExportService.csv([[["Name", "Note"], ["Иванов, И.", "said \"hi\""]]])
        #expect(csv == "\u{FEFF}Name,Note\r\n\"Иванов, И.\",\"said \"\"hi\"\"\"")
    }

    @Test func csvSeparatesTablesWithEmptyLine() {
        let csv = TableExportService.csv([[["a"]], [["b"]]])
        #expect(csv == "\u{FEFF}a\r\n\r\nb")
    }

    @Test func encryptedPDFNeedsPassword() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
        }
        let data = PDFService.generatePDF(from: [image], pageSize: .a4)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("locked-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(PDFService.encrypt(data, password: "secret", to: url))
        let document = try #require(PDFDocument(url: url))
        #expect(document.isLocked)
        #expect(!document.unlock(withPassword: "wrong"))
        #expect(document.unlock(withPassword: "secret"))
    }

    @Test func pdfImportRendersEveryPage() throws {
        let images = (0..<3).map { _ in
            UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PDFService.generatePDF(from: images, pageSize: .a4).write(to: url)

        let pages = ImportService.processPDF(at: url)
        #expect(pages.count == 3)
        #expect(pages.allSatisfy { $0.originalImageData == nil })
    }
}
