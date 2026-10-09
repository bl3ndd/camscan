import Vision
import UIKit

/// A recognized line with its box normalized to 0...1, top-left origin.
nonisolated struct TextLine: Codable, Equatable, Sendable {
    var text: String
    var box: CGRect
}

nonisolated enum OCRService {
    /// Synchronous and slow: call from a detached task.
    static func recognizeLines(in image: UIImage) throws -> [TextLine] {
        guard let cgImage = image.upright().cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision has a bottom-left origin.
            let box = observation.boundingBox
            return TextLine(
                text: text,
                box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            )
        }
    }

    static func text(of lines: [TextLine]) -> String {
        lines.map(\.text).joined(separator: "\n")
    }
}
