import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageFilter: String, CaseIterable, Identifiable {
    case original = "Original"
    case grayscale = "Black & White"
    case highContrast = "High Contrast"
    case sharpen = "Sharpen"
    case noir = "Noir"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .original: "photo"
        case .grayscale: "circle.lefthalf.filled"
        case .highContrast: "sun.max.fill"
        case .sharpen: "triangle.fill"
        case .noir: "moon.fill"
        }
    }
}

struct ImageFilterService {
    private static let context = CIContext()

    static func apply(_ filter: ImageFilter, to image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let filtered: CIImage? = switch filter {
        case .original:
            ciImage
        case .grayscale:
            applyGrayscale(ciImage)
        case .highContrast:
            applyHighContrast(ciImage)
        case .sharpen:
            applySharpen(ciImage)
        case .noir:
            applyNoir(ciImage)
        }

        guard let output = filtered,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func applyGrayscale(_ input: CIImage) -> CIImage? {
        let filter = CIFilter.colorMonochrome()
        filter.inputImage = input
        filter.color = CIColor(red: 0.7, green: 0.7, blue: 0.7)
        filter.intensity = 1.0
        return filter.outputImage
    }

    private static func applyHighContrast(_ input: CIImage) -> CIImage? {
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.contrast = 1.8
        filter.brightness = 0.05
        filter.saturation = 0
        return filter.outputImage
    }

    private static func applySharpen(_ input: CIImage) -> CIImage? {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = input
        filter.sharpness = 0.8
        return filter.outputImage
    }

    private static func applyNoir(_ input: CIImage) -> CIImage? {
        let filter = CIFilter.photoEffectNoir()
        filter.inputImage = input
        return filter.outputImage
    }
}
