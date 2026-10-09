import UIKit
import PencilKit
import SwiftUI

/// The user's saved signature, kept as a PencilKit drawing in Application Support.
enum SignatureStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("signature.drawing")
    }

    static func load() -> PKDrawing? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PKDrawing(data: data)
    }

    static func save(_ drawing: PKDrawing) throws {
        try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try drawing.dataRepresentation().write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Signature cropped to its strokes, in black ink, ready to place on a page.
    static func image(from drawing: PKDrawing) -> UIImage? {
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard !drawing.strokes.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
        // Render in light mode so the ink is dark regardless of the system appearance.
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 3)
        }
        return image
    }
}

/// PencilKit canvas; finger drawing allowed.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var showsToolPicker = false
    var tool: PKTool = PKInkingTool(.pen, color: .black, width: 4)

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = tool
        canvas.drawing = drawing
        canvas.delegate = context.coordinator

        if showsToolPicker {
            context.coordinator.toolPicker.addObserver(canvas)
            context.coordinator.toolPicker.setVisible(true, forFirstResponder: canvas)
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let drawing: Binding<PKDrawing>
        let toolPicker = PKToolPicker()

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
