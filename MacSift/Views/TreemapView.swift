import SwiftUI

struct TreemapItem: Identifiable {
    let id: String
    let label: String
    let size: Int64
    let color: Color
    let category: FileCategory
}

struct TreemapRect {
    let item: TreemapItem
    let rect: CGRect
}

struct TreemapView: View {
    let result: ScanResult
    @Binding var selectedCategory: FileCategory?
    @State private var hoveredItem: String?

    private var items: [TreemapItem] {
        result.sizeByCategory
            .filter { $0.value > 0 }
            .map { category, size in
                TreemapItem(
                    id: category.rawValue,
                    label: category.label,
                    size: size,
                    color: category.displayColor,
                    category: category
                )
            }
            .sorted { $0.size > $1.size }
    }

    var body: some View {
        GeometryReader { geometry in
            let rects = squarify(items: items, in: CGRect(origin: .zero, size: geometry.size))

            ZStack {
                Canvas { context, _ in
                    for treemapRect in rects {
                        let insetRect = treemapRect.rect.insetBy(dx: 1.5, dy: 1.5)
                        let path = Path(roundedRect: insetRect, cornerRadius: 4)

                        let isHovered = hoveredItem == treemapRect.item.id
                        let opacity: Double = isHovered ? 0.95 : 0.75

                        context.fill(path, with: .color(treemapRect.item.color.opacity(opacity)))

                        if insetRect.width > 60 && insetRect.height > 30 {
                            let text = Text(treemapRect.item.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            context.draw(
                                context.resolve(text),
                                at: CGPoint(x: insetRect.midX, y: insetRect.midY - 8)
                            )

                            let sizeText = Text(treemapRect.item.size.formattedFileSize)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                            context.draw(
                                context.resolve(sizeText),
                                at: CGPoint(x: insetRect.midX, y: insetRect.midY + 8)
                            )
                        }
                    }
                }

                ForEach(rects, id: \.item.id) { treemapRect in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: treemapRect.rect.width, height: treemapRect.rect.height)
                        .position(
                            x: treemapRect.rect.midX,
                            y: treemapRect.rect.midY
                        )
                        .onHover { isHovered in
                            hoveredItem = isHovered ? treemapRect.item.id : nil
                        }
                        .onTapGesture {
                            selectedCategory = treemapRect.item.category
                        }
                        .help("\(treemapRect.item.label): \(treemapRect.item.size.formattedFileSize)")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func squarify(items: [TreemapItem], in bounds: CGRect) -> [TreemapRect] {
        guard !items.isEmpty else { return [] }
        guard bounds.width > 0 && bounds.height > 0 else { return [] }

        let totalSize = items.reduce(0 as Int64) { $0 + $1.size }
        guard totalSize > 0 else { return [] }

        var results: [TreemapRect] = []
        var remaining = items
        var currentBounds = bounds
        let totalArea = bounds.width * bounds.height

        while !remaining.isEmpty {
            let isWide = currentBounds.width >= currentBounds.height
            let sideLength = isWide ? currentBounds.height : currentBounds.width

            let remainingTotal = remaining.reduce(0 as Int64) { $0 + $1.size }
            var row: [TreemapItem] = []
            var rowSize: Int64 = 0

            for item in remaining {
                let newRow = row + [item]
                let newRowSize = rowSize + item.size

                let currentWorst = row.isEmpty
                    ? CGFloat.greatestFiniteMagnitude
                    : worstAspectRatio(row, rowSize: rowSize, totalSize: remainingTotal, sideLength: sideLength, totalArea: totalArea)
                let newWorst = worstAspectRatio(newRow, rowSize: newRowSize, totalSize: remainingTotal, sideLength: sideLength, totalArea: totalArea)

                if row.isEmpty || newWorst <= currentWorst {
                    row = newRow
                    rowSize = newRowSize
                } else {
                    break
                }
            }

            let rowFraction = Double(rowSize) / Double(remainingTotal)

            if isWide {
                let rowWidth = currentBounds.width * rowFraction
                var y = currentBounds.minY

                for item in row {
                    let itemFraction = Double(item.size) / Double(rowSize)
                    let itemHeight = currentBounds.height * itemFraction
                    results.append(TreemapRect(
                        item: item,
                        rect: CGRect(x: currentBounds.minX, y: y, width: rowWidth, height: itemHeight)
                    ))
                    y += itemHeight
                }

                currentBounds = CGRect(
                    x: currentBounds.minX + rowWidth,
                    y: currentBounds.minY,
                    width: currentBounds.width - rowWidth,
                    height: currentBounds.height
                )
            } else {
                let rowHeight = currentBounds.height * rowFraction
                var x = currentBounds.minX

                for item in row {
                    let itemFraction = Double(item.size) / Double(rowSize)
                    let itemWidth = currentBounds.width * itemFraction
                    results.append(TreemapRect(
                        item: item,
                        rect: CGRect(x: x, y: currentBounds.minY, width: itemWidth, height: rowHeight)
                    ))
                    x += itemWidth
                }

                currentBounds = CGRect(
                    x: currentBounds.minX,
                    y: currentBounds.minY + rowHeight,
                    width: currentBounds.width,
                    height: currentBounds.height - rowHeight
                )
            }

            remaining = Array(remaining.dropFirst(row.count))
        }

        return results
    }

    private func worstAspectRatio(_ row: [TreemapItem], rowSize: Int64, totalSize: Int64, sideLength: CGFloat, totalArea: CGFloat) -> CGFloat {
        guard !row.isEmpty, rowSize > 0, totalSize > 0, sideLength > 0 else { return CGFloat.greatestFiniteMagnitude }

        let rowArea = totalArea * Double(rowSize) / Double(totalSize)
        let rowLength = rowArea / Double(sideLength)
        guard rowLength > 0 else { return CGFloat.greatestFiniteMagnitude }

        var worst: CGFloat = 0
        for item in row {
            let itemArea = totalArea * Double(item.size) / Double(totalSize)
            let itemLength = itemArea / rowLength
            guard itemLength > 0 else { continue }

            let aspect = max(itemLength / rowLength, rowLength / itemLength)
            worst = max(worst, aspect)
        }

        return worst
    }
}
