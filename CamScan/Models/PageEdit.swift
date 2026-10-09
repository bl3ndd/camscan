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

/// An image drawn on top of the finished page: a placed signature or a PencilKit drawing.
nonisolated struct PageOverlay: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case signature
        case drawing
    }

    var id = UUID()
    var kind: Kind
    /// PNG with a transparent background.
    var imageData: Data
    /// Normalized to the finished page, top-left origin.
    var rect: CGRect
    /// PencilKit drawing, kept so drawings stay editable.
    var drawingData: Data?
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
    var overlays: [PageOverlay] = []

    init() {}

    init(quad: Quad, filter: ImageFilter) {
        self.quad = quad
        self.filter = filter
    }

    /// Missing keys fall back to defaults, so edits saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quad = try container.decodeIfPresent(Quad.self, forKey: .quad) ?? .full
        filter = (try? container.decodeIfPresent(ImageFilter.self, forKey: .filter)) ?? .original
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        rotation = try container.decodeIfPresent(Int.self, forKey: .rotation) ?? 0
        overlays = try container.decodeIfPresent([PageOverlay].self, forKey: .overlays) ?? []
    }

    var drawing: PageOverlay? {
        overlays.first { $0.kind == .drawing }
    }

    /// Replaces the page's drawing; `nil` removes it.
    mutating func setDrawing(_ overlay: PageOverlay?) {
        overlays.removeAll { $0.kind == .drawing }
        if let overlay {
            overlays.append(overlay)
        }
    }
}
