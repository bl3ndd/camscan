import SwiftUI

/// Drag the four corners onto the document's edges; the page is then perspective-corrected.
struct CropView: View {
    let image: UIImage
    var onDone: (Quad) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quad: Quad
    @State private var isDetecting = false
    @State private var detectionFailed = false

    init(image: UIImage, quad: Quad, onDone: @escaping (Quad) -> Void) {
        self.image = image
        self.onDone = onDone
        _quad = State(initialValue: quad)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let rect = fittedRect(for: image.size, in: proxy.size)
                let points = quad.corners.map { viewPoint($0, in: rect) }

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    QuadShape(points: points)
                        .fill(Color.brand.opacity(0.15))
                    QuadShape(points: points)
                        .stroke(Color.brand, lineWidth: 2)

                    ForEach(0..<4, id: \.self) { index in
                        handle
                            .position(points[index])
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                                    .onChanged { value in
                                        quad.setCorner(index, to: normalizedPoint(value.location, in: rect))
                                    }
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .coordinateSpace(.named("crop"))
            }
            .padding(24)
            .background(Color.black)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(quad)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        detectEdges()
                    } label: {
                        Label("Auto", systemImage: "viewfinder")
                    }
                    .disabled(isDetecting)

                    Spacer()

                    Button {
                        quad = .full
                    } label: {
                        Label("Full Page", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            .alert("No document found", isPresented: $detectionFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Drag the corners to the edges of the document.")
            }
        }
    }

    private var handle: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color.brand, lineWidth: 3))
                .shadow(radius: 2)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private func detectEdges() {
        isDetecting = true
        let image = image
        Task {
            let detected = await Task.detached(priority: .userInitiated) {
                DocumentDetector.detectQuad(in: image)
            }.value
            if let detected {
                quad = detected
            } else {
                detectionFailed = true
            }
            isDetecting = false
        }
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

    private func viewPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func normalizedPoint(_ location: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((location.x - rect.minX) / rect.width, 0), 1),
            y: min(max((location.y - rect.minY) / rect.height, 0), 1)
        )
    }
}

nonisolated struct QuadShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }
}
