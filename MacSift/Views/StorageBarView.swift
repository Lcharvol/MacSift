import SwiftUI

struct StorageBarView: View {
    let result: ScanResult
    @Binding var selectedCategory: FileCategory?

    @State private var hoveredCategory: FileCategory?

    private var entries: [(FileCategory, Int64)] {
        FileCategory.allCases.compactMap { category in
            let size = result.sizeByCategory[category] ?? 0
            return size > 0 ? (category, size) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    private var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bar
            legend
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Storage Found")
                .font(.headline)
            Spacer()
            Text("\(totalSize.formattedFileSize) recoverable")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(totalSize, 1)
            let spacing: CGFloat = 2

            // Calculate segment widths up front
            let segments: [(FileCategory, CGFloat)] = entries.map { entry in
                let fraction = Double(entry.1) / Double(total)
                return (entry.0, max(4, width * CGFloat(fraction) - spacing))
            }

            HStack(spacing: spacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let (category, segWidth) = segment
                    let isHovered = hoveredCategory == category
                    let isSelected = selectedCategory == category

                    Rectangle()
                        .fill(category.displayColor)
                        .frame(width: segWidth)
                        .opacity((isHovered || isSelected) ? 1.0 : 0.85)
                        .onHover { hovering in
                            hoveredCategory = hovering ? category : nil
                        }
                        .onTapGesture {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        }
                        .help("\(category.label): \((result.sizeByCategory[category] ?? 0).formattedFileSize)")
                        .animation(.easeOut(duration: 0.15), value: isHovered)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                }

                if entries.isEmpty {
                    Rectangle()
                        .fill(.quaternary)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 18)
    }

    // MARK: - Legend

    private var legend: some View {
        FlowLayout(spacing: 14) {
            ForEach(entries, id: \.0) { entry in
                let (category, size) = entry
                let isSelected = selectedCategory == category

                Button {
                    selectedCategory = isSelected ? nil : category
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(category.displayColor)
                            .frame(width: 8, height: 8)
                        Text(category.label)
                            .font(.callout)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        Text(size.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - FlowLayout (simple wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth - spacing)
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth - spacing)
        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
