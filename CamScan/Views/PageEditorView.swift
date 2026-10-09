import SwiftUI

/// Crop, rotate, filter and tone a page. Edits are applied to the original, so they can always be undone.
struct PageEditorView: View {
    let source: UIImage
    var onApply: (PageEdit, UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edit: PageEdit
    @State private var preview: UIImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var showCrop = false
    @State private var isSaving = false

    /// Downscaled copy for fast previews; the final render uses `source`.
    private let previewSource: UIImage

    init(source: UIImage, edit: PageEdit, onApply: @escaping (PageEdit, UIImage) -> Void) {
        self.source = source
        self.onApply = onApply
        self.previewSource = source.upright(maxDimension: 1200)
        _edit = State(initialValue: edit)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

                controls
            }
            .navigationTitle("Edit Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Apply") { save() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCrop) {
                CropView(image: previewSource, quad: edit.quad) { quad in
                    edit.quad = quad
                }
            }
            .onAppear { updatePreview(debounce: false) }
            .onChange(of: edit) { updatePreview(debounce: true) }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                toolButton("Crop", icon: "crop") { showCrop = true }
                toolButton("Rotate", icon: "rotate.right") { edit.rotation = (edit.rotation + 1) % 4 }
                toolButton("Reset", icon: "arrow.uturn.backward") {
                    // Reset crop and tone; signatures and drawings have their own removal.
                    let overlays = edit.overlays
                    edit = PageEdit()
                    edit.overlays = overlays
                }
                if !edit.overlays.isEmpty {
                    toolButton("Remove Ink", icon: "signature") { edit.overlays = [] }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(ImageFilter.allCases) { filter in
                        filterButton(filter)
                    }
                }
                .padding(.horizontal)
            }

            sliderRow(icon: "sun.max", value: $edit.brightness, range: -0.3...0.3)
            sliderRow(icon: "circle.lefthalf.filled", value: $edit.contrast, range: 0.5...1.5)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func toolButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }

    private func filterButton(_ filter: ImageFilter) -> some View {
        Button {
            edit.filter = filter
        } label: {
            VStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(edit.filter == filter ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(edit.filter == filter ? .blue : .clear, lineWidth: 2)
                    )

                Text(filter.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(icon: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
        .padding(.horizontal)
    }

    /// Cancels the previous render so a slow result never overwrites a newer one.
    private func updatePreview(debounce: Bool) {
        previewTask?.cancel()
        let edit = edit
        let input = previewSource
        previewTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(60))
            }
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                ImageFilterService.render(input, edit: edit)
            }.value
            guard !Task.isCancelled else { return }
            preview = rendered
        }
    }

    private func save() {
        isSaving = true
        previewTask?.cancel()
        let edit = edit
        let source = source
        Task {
            let rendered = await Task.detached(priority: .userInitiated) {
                ImageFilterService.render(source, edit: edit)
            }.value
            onApply(edit, rendered)
            dismiss()
        }
    }
}
