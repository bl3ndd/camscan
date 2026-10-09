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
    /// Small renders of the page with each filter, so the choice is visual.
    @State private var thumbnails: [ImageFilter: UIImage] = [:]

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
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))

                controls
            }
            .navigationTitle("Edit")
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
            .task(id: ThumbnailKey(quad: edit.quad, rotation: edit.rotation)) { await updateThumbnails() }
            .onChange(of: edit) { updatePreview(debounce: true) }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                toolButton("Crop", icon: "crop") { showCrop = true }
                    .accessibilityIdentifier("cropTool")
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
                Color(.secondarySystemBackground)
                    .frame(width: 56, height: 72)
                    .overlay {
                        if let thumbnail = thumbnails[filter] {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: filter.icon)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(edit.filter == filter ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: edit.filter == filter ? 3 : 1)
                    )

                Text(filter.title)
                    .font(.caption2.weight(edit.filter == filter ? .semibold : .regular))
                    .foregroundStyle(edit.filter == filter ? Color.accentColor : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.rawValue)")
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

    /// Re-rendered only when the crop or rotation changes; tone sliders don't affect the choice of filter.
    private func updateThumbnails() async {
        let base: PageEdit = {
            var base = PageEdit()
            base.quad = edit.quad
            base.rotation = edit.rotation
            return base
        }()
        let small = previewSource.upright(maxDimension: 240)
        let rendered = await Task.detached(priority: .utility) {
            var result: [ImageFilter: UIImage] = [:]
            for filter in ImageFilter.allCases {
                var edit = base
                edit.filter = filter
                result[filter] = ImageFilterService.render(small, edit: edit)
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        thumbnails = rendered
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

private struct ThumbnailKey: Equatable {
    let quad: Quad
    let rotation: Int
}
