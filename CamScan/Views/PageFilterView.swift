import SwiftUI

struct PageFilterView: View {
    let originalImage: UIImage
    var onApply: (UIImage, ImageFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: ImageFilter = .original
    @State private var filteredImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview
                if let image = filteredImage ?? Optional(originalImage) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }

                // Filter picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(ImageFilter.allCases) { filter in
                            filterButton(filter)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(filteredImage ?? originalImage, selectedFilter)
                        dismiss()
                    }
                }
            }
        }
    }

    private func filterButton(_ filter: ImageFilter) -> some View {
        Button {
            selectedFilter = filter
            Task.detached {
                let result = ImageFilterService.apply(filter, to: originalImage)
                await MainActor.run { filteredImage = result }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(selectedFilter == filter ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedFilter == filter ? .blue : .clear, lineWidth: 2)
                    )

                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
