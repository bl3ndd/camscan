import SwiftUI
import PencilKit

/// Draw, highlight and erase on a page with the PencilKit tool picker.
struct AnnotateView: View {
    /// The page without its current drawing.
    let page: UIImage
    var onDone: (PageOverlay?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero
    /// Saved drawing in reference coordinates (page width = `referenceWidth`).
    private let savedDrawing: PKDrawing?

    /// Drawings are stored at this page width so they reload aligned on any screen size.
    private static let referenceWidth: CGFloat = 1000

    init(page: UIImage, existing: PageOverlay?, onDone: @escaping (PageOverlay?) -> Void) {
        self.page = page
        self.onDone = onDone
        self.savedDrawing = existing?.drawingData.flatMap { try? PKDrawing(data: $0) }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let rect = fittedRect(for: page.size, in: proxy.size)
                ZStack {
                    Image(uiImage: page)
                        .resizable()
                    CanvasView(
                        drawing: $drawing,
                        showsToolPicker: true,
                        tool: PKInkingTool(.marker, color: .systemYellow, width: 20)
                    )
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .onAppear { setCanvasSize(rect.size) }
                .onChange(of: rect.size) { setCanvasSize(rect.size) }
            }
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(makeOverlay())
                        dismiss()
                    }
                }
            }
        }
    }

    private func setCanvasSize(_ size: CGSize) {
        let isFirstLayout = canvasSize == .zero
        canvasSize = size
        if isFirstLayout, let savedDrawing, size.width > 0 {
            let scale = size.width / Self.referenceWidth
            drawing = savedDrawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    /// Drawings are stored in canvas points; the canvas always shows the whole page,
    /// so the overlay covers the full page and stays aligned at any screen size.
    private func makeOverlay() -> PageOverlay? {
        guard !drawing.strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let scale = page.size.width / canvasSize.width
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: scale)
        }
        guard let data = image?.pngData() else { return nil }

        let toReference = Self.referenceWidth / canvasSize.width
        let normalized = drawing.transformed(using: CGAffineTransform(scaleX: toReference, y: toReference))
        return PageOverlay(
            kind: .drawing,
            imageData: data,
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            drawingData: normalized.dataRepresentation()
        )
    }

    private func fittedRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
