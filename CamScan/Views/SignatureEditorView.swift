import SwiftUI
import PencilKit

/// Draw and save the signature once; it can then be placed on any page.
struct SignatureEditorView: View {
    var onSaved: ((UIImage) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = SignatureStore.load() ?? PKDrawing()
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sign with your finger or Apple Pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white)
                    Rectangle()
                        .fill(.gray.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 48)
                    CanvasView(drawing: $drawing)
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

                Spacer()
            }
            .padding()
            .navigationTitle("My Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(drawing.strokes.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear", role: .destructive) {
                        drawing = PKDrawing()
                    }
                }
            }
            .alert("Couldn't save the signature", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() {
        do {
            try SignatureStore.save(drawing)
            if let image = SignatureStore.image(from: drawing) {
                onSaved?(image)
            }
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
