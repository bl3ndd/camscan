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
