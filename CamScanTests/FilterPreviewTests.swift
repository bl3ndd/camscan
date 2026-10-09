import XCTest
import UIKit
@testable import CamScan

/// Runs a synthetic photo of a document through auto-crop and every filter and
/// attaches the results, so CI shows what the filters actually do to a page.
final class FilterPreviewTests: XCTestCase {

    func testAutoCropFindsTiltedPage() throws {
        let photo = SampleDocuments.photo(of: SampleDocuments.invoice)
        attach(photo, "filter-00-photo")

        let quad = try XCTUnwrap(DocumentDetector.detectQuad(in: photo), "Page not found on the photo")
        let cropped = ImageFilterService.render(photo, edit: PageEdit(quad: quad, filter: .original))
        attach(cropped, "filter-01-cropped")

        // The page is A4 (1 : 1.414); after perspective correction it should be close to that.
        let aspect = cropped.size.height / cropped.size.width
        XCTAssertEqual(aspect, 1754.0 / 1240.0, accuracy: 0.12, "Cropped aspect \(aspect)")
    }

    func testFiltersOnPhoto() throws {
        let photo = SampleDocuments.photo(of: SampleDocuments.invoice)
        let quad = DocumentDetector.detectQuad(in: photo) ?? .full

        for (index, filter) in ImageFilter.allCases.enumerated() {
            let rendered = ImageFilterService.render(photo, edit: PageEdit(quad: quad, filter: filter))
            attach(rendered, "filter-\(String(format: "%02d", index + 2))-\(filter.rawValue)")
        }

        // Flattening should even out the light: paper in the shadowed corner should
        // come out nearly as bright as in the lit one.
        let auto = ImageFilterService.render(photo, edit: PageEdit(quad: quad, filter: .auto))
        let lit = brightness(of: auto, atFraction: CGPoint(x: 0.9, y: 0.05))
        let shaded = brightness(of: auto, atFraction: CGPoint(x: 0.05, y: 0.95))
        XCTAssertGreaterThan(shaded, 0.8, "Shaded paper is still dark: \(shaded)")
        XCTAssertLessThan(abs(lit - shaded), 0.15, "Uneven light: lit \(lit), shaded \(shaded)")
    }

    // MARK: - Helpers

    private func attach(_ image: UIImage, _ name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Average brightness of a small patch around a point given in fractions of the size.
    private func brightness(of image: UIImage, atFraction point: CGPoint) -> CGFloat {
        guard let cgImage = image.cgImage else { return -1 }
        let x = Int(point.x * CGFloat(cgImage.width - 8))
        let y = Int(point.y * CGFloat(cgImage.height - 8))
        guard let patch = cgImage.cropping(to: CGRect(x: x, y: y, width: 8, height: 8)) else { return -1 }

        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let context = CGContext(
            data: &pixels, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(patch, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0) { total, i in
            total + Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
        }
        return CGFloat(sum) / CGFloat(8 * 8 * 3 * 255)
    }
}
