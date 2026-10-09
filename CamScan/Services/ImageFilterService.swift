import UIKit
import CoreImage

nonisolated enum ImageFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case original = "Original"
    case auto = "Auto"
    case magicColor = "Magic Color"
    case grayscale = "Grayscale"
    case blackWhite = "B&W"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .original: "photo"
        case .auto: "wand.and.stars"
        case .magicColor: "paintpalette"
        case .grayscale: "circle.lefthalf.filled"
        case .blackWhite: "doc.plaintext"
        }
    }
}

nonisolated enum ImageFilterService {
    nonisolated(unsafe) private static let context = CIContext()

    /// Applies crop (perspective correction), tone and rotation to an upright source image.
    static func render(_ source: UIImage, edit: PageEdit) -> UIImage {
        let source = source.upright()
        guard let cgImage = source.cgImage else { return source }

        var image = CIImage(cgImage: cgImage)
        image = perspectiveCorrected(image, quad: edit.quad)
        image = toned(image, edit: edit)
        image = rotated(image, quarterTurns: edit.rotation)

        guard let output = context.createCGImage(image, from: image.extent.integral) else {
            return source
        }
        return UIImage(cgImage: output)
    }

    // MARK: - Private

    private static func perspectiveCorrected(_ image: CIImage, quad: Quad) -> CIImage {
        guard !quad.isFull else { return image }
        let width = image.extent.width
        let height = image.extent.height
        // Core Image has a bottom-left origin.
        func vector(_ point: CGPoint) -> CIVector {
            CIVector(x: point.x * width, y: (1 - point.y) * height)
        }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(quad.topLeft),
            "inputTopRight": vector(quad.topRight),
            "inputBottomRight": vector(quad.bottomRight),
            "inputBottomLeft": vector(quad.bottomLeft),
        ])
        return movedToOrigin(corrected)
    }

    private static func toned(_ image: CIImage, edit: PageEdit) -> CIImage {
        var result = image
        var saturation = 1.0
        var contrast = edit.contrast

        switch edit.filter {
        case .original:
            break
        case .auto:
            result = flattenIllumination(result)
            contrast *= 1.1
        case .magicColor:
            result = flattenIllumination(result)
            saturation = 1.4
            contrast *= 1.25
        case .grayscale:
            result = flattenIllumination(result)
            saturation = 0
            contrast *= 1.15
        case .blackWhite:
            result = flattenIllumination(result)
            saturation = 0
        }

        if saturation != 1 || contrast != 1 || edit.brightness != 0 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputContrastKey: contrast,
                kCIInputBrightnessKey: edit.brightness,
            ])
        }

        if edit.filter == .blackWhite {
            // After flattening the paper is ~1.0, so a fixed threshold separates ink reliably.
            result = result.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.72])
        }
        return result
    }

    /// Evens out lighting: estimates the paper (text erased by a max filter, then blurred)
    /// and divides the image by it, so shadows and uneven light turn into white paper.
    private static func flattenIllumination(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        guard longSide > 0 else { return image }

        // Estimate the background on a small copy: faster and naturally smooth.
        let scale = min(1, 512 / longSide)
        let background = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 5])
            .applyingGaussianBlur(sigma: 10)
            .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            .cropped(to: extent)

        // CIDivideBlendMode computes background / input, i.e. image / estimated paper.
        return background
            .applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
    }

    private static func rotated(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let result: CIImage = switch ((quarterTurns % 4) + 4) % 4 {
        case 1: image.oriented(.right)
        case 2: image.oriented(.down)
        case 3: image.oriented(.left)
        default: image
        }
        return movedToOrigin(result)
    }

    private static func movedToOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}

extension UIImage {
    /// Redraws the image with `.up` orientation, shrinking it so the long side is at most `maxDimension` pixels.
    nonisolated func upright(maxDimension: CGFloat? = nil) -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        var factor: CGFloat = 1
        if let maxDimension, max(pixelSize.width, pixelSize.height) > 0 {
            factor = min(1, maxDimension / max(pixelSize.width, pixelSize.height))
        }
        if imageOrientation == .up && factor == 1 && cgImage != nil {
            return self
        }

        let target = CGSize(
            width: max(1, (pixelSize.width * factor).rounded()),
            height: max(1, (pixelSize.height * factor).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
