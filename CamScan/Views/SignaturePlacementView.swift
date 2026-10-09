import SwiftUI

/// Drag the signature into place and pinch to resize it.
struct SignaturePlacementView: View {
    let page: UIImage
    let signature: UIImage
    var onPlace: (CGRect) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Normalized center on the page.
    @State private var center = CGPoint(x: 0.7, y: 0.85)
    /// Signature width as a fraction of the page width.
    @State private var width: CGFloat = 0.35
    @State private var dragStart: CGPoint?
    @State private var widthAtPinchStart: CGFloat?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let rect = fittedRect(for: page.size, in: proxy.size)
                let signatureSize = CGSize(
                    width: width * rect.width,
                    height: width * rect.width * signature.size.height / max(signature.size.width, 1)
                )

                ZStack {
                    Image(uiImage: page)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    Image(uiImage: signature)
                        .resizable()
                        .frame(width: signatureSize.width, height: signatureSize.height)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .position(x: rect.minX + center.x * rect.width, y: rect.minY + center.y * rect.height)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let start = dragStart ?? center
                                    dragStart = start
                                    center = CGPoint(
                                        x: min(max(start.x + value.translation.width / rect.width, 0), 1),
                                        y: min(max(start.y + value.translation.height / rect.height, 0), 1)
                                    )
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = widthAtPinchStart ?? width
                            widthAtPinchStart = start
                            width = min(max(start * value.magnification, 0.08), 0.95)
                        }
                        .onEnded { _ in widthAtPinchStart = nil }
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Place Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onPlace(normalizedRect)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("Drag to move, pinch to resize")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var normalizedRect: CGRect {
        let pageAspect = page.size.width / max(page.size.height, 1)
        let height = width * signature.size.height / max(signature.size.width, 1) * pageAspect
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
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
