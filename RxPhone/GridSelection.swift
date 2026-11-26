import CoreGraphics

/// Pure math behind drag-to-select and auto-scroll in the library grid, kept
/// out of the view so it can be unit tested.
nonisolated enum GridSelection {
    /// Column count and cell size for `GridItem.adaptive(minimum:)` at a width.
    static func layout(width: CGFloat, minCellSize: CGFloat, spacing: CGFloat) -> (columns: Int, cell: CGFloat) {
        let columns = max(Int((width + spacing) / (minCellSize + spacing)), 1)
        let cell = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        return (columns, cell)
    }

    /// The item under `point` (same coordinate space as `gridFrame`). Points
    /// above the grid map to the first row, beyond the end to the last item.
    static func index(at point: CGPoint, gridFrame: CGRect, itemCount: Int,
                      minCellSize: CGFloat, spacing: CGFloat) -> Int? {
        guard gridFrame.width > 0, itemCount > 0 else { return nil }
        let (columns, cell) = layout(width: gridFrame.width, minCellSize: minCellSize, spacing: spacing)
        let x = point.x - gridFrame.minX
        let y = max(point.y - gridFrame.minY, 0)
        let column = min(max(Int(x / (cell + spacing)), 0), columns - 1)
        let row = Int(y / (cell + spacing))
        return min(row * columns + column, itemCount - 1)
    }

    /// Selection while dragging from `start` to `current`: every item in
    /// between is added (or removed), and items outside go back to `base`.
    static func select<ID: Hashable>(ids: [ID], from start: Int, to current: Int,
                                     adding: Bool, base: Set<ID>) -> Set<ID> {
        let range = Set(ids[min(start, current)...max(start, current)])
        return adding ? base.union(range) : base.subtracting(range)
    }

    /// Auto-scroll speed for a finger at `fingerY`: 0 in the middle, ramping to
    /// ±`maxStep` points per frame at the edges of the visible band.
    static func autoScrollStep(fingerY: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat,
                               edge: CGFloat, maxStep: CGFloat) -> CGFloat {
        if fingerY < visibleTop + edge {
            return -maxStep * min((visibleTop + edge - fingerY) / edge, 1)
        }
        if fingerY > visibleBottom - edge {
            return maxStep * min((fingerY - (visibleBottom - edge)) / edge, 1)
        }
        return 0
    }
}
