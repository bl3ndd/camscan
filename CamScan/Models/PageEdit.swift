import Foundation
import CoreGraphics

/// Corners of the document inside the source image, normalized to 0...1 with a top-left origin.
nonisolated struct Quad: Codable, Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let full = Quad(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 1, y: 0),
        bottomRight: CGPoint(x: 1, y: 1),
        bottomLeft: CGPoint(x: 0, y: 1)
    )

    var isFull: Bool { self == .full }

    /// Clockwise from top-left.
    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    mutating func setCorner(_ index: Int, to point: CGPoint) {
        switch index {
        case 0: topLeft = point
        case 1: topRight = point
        case 2: bottomRight = point
        default: bottomLeft = point
        }
    }
}

/// Non-destructive page edits, applied to the page's original image by `ImageFilterService.render`.
nonisolated struct PageEdit: Codable, Equatable, Sendable {
    var quad: Quad = .full
    var filter: ImageFilter = .original
    /// -0.3 ... 0.3
    var brightness: Double = 0
    /// 0.5 ... 1.5
    var contrast: Double = 1
    /// Clockwise quarter turns, 0...3.
    var rotation: Int = 0
}
