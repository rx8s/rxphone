import CoreGraphics
import Foundation
import Testing
@testable import RxPhone

/// Tests for drag-to-select and auto-scroll math in the library grid.
@Suite("GridSelection")
struct GridSelectionTests {
    // iPhone 18 Pro grid: 402 pt wide, adaptive cells ≥ 100 pt, 2 pt spacing
    // → 3 columns of 132.67 pt. The grid starts 172 pt down (below the title).
    let frame = CGRect(x: 0, y: 172, width: 402, height: 2000)
    let step: CGFloat = 132.67 + 2

    private func index(x: CGFloat, y: CGFloat, count: Int = 60) -> Int? {
        GridSelection.index(at: CGPoint(x: x, y: y), gridFrame: frame, itemCount: count,
                            minCellSize: 100, spacing: 2)
    }

    // MARK: - Layout

    @Test("Matches GridItem.adaptive: as many columns as fit the minimum size")
    func layout() {
        let phone = GridSelection.layout(width: 402, minCellSize: 100, spacing: 2)
        #expect(phone.columns == 3)
        #expect(abs(phone.cell - 132.67) < 0.01)
        #expect(GridSelection.layout(width: 874, minCellSize: 100, spacing: 2).columns == 8)
        #expect(GridSelection.layout(width: 50, minCellSize: 100, spacing: 2).columns == 1)
    }

    // MARK: - Point → item

    @Test("Points map to the cell under them, row by row")
    func cellCenters() {
        #expect(index(x: 66, y: 172 + 66) == 0)
        #expect(index(x: 66 + step, y: 172 + 66) == 1)
        #expect(index(x: 66 + 2 * step, y: 172 + 66) == 2)
        #expect(index(x: 66, y: 172 + 66 + step) == 3)
        #expect(index(x: 66 + step, y: 172 + 66 + 2 * step) == 7)
    }

    @Test("Points outside the grid clamp to the nearest valid item")
    func clamping() {
        #expect(index(x: -20, y: 172 + 66) == 0)          // left of the grid
        #expect(index(x: 500, y: 172 + 66) == 2)          // right of the grid
        #expect(index(x: 66 + step, y: 40) == 1)          // above the grid → first row
        #expect(index(x: 66, y: 172 + 66 + 50 * step) == 59) // past the end → last item
        #expect(index(x: 66 + 2 * step, y: 172 + 66 + step, count: 4) == 3) // short last row
    }

    @Test("Scrolling moves the grid frame, and the same screen point picks a later row")
    func scrolledGrid() {
        let scrolled = frame.offsetBy(dx: 0, dy: -3 * step)
        let i = GridSelection.index(at: CGPoint(x: 66, y: 172 + 66), gridFrame: scrolled,
                                    itemCount: 60, minCellSize: 100, spacing: 2)
        #expect(i == 9)
    }

    @Test("No items or no width gives no index")
    func emptyGrid() {
        #expect(index(x: 66, y: 200, count: 0) == nil)
        #expect(GridSelection.index(at: .zero, gridFrame: .zero, itemCount: 10,
                                    minCellSize: 100, spacing: 2) == nil)
    }

    // MARK: - Range selection

    let ids = ["a", "b", "c", "d", "e", "f"]

    @Test("Dragging forward or backward selects every item in between")
    func selectRange() {
        #expect(GridSelection.select(ids: ids, from: 1, to: 3, adding: true, base: []) == ["b", "c", "d"])
        #expect(GridSelection.select(ids: ids, from: 3, to: 1, adding: true, base: []) == ["b", "c", "d"])
        #expect(GridSelection.select(ids: ids, from: 2, to: 2, adding: true, base: []) == ["c"])
    }

    @Test("Selection made before the drag is kept")
    func keepsBase() {
        #expect(GridSelection.select(ids: ids, from: 3, to: 4, adding: true, base: ["a"]) == ["a", "d", "e"])
    }

    @Test("Starting on a selected item deselects the range instead")
    func deselectRange() {
        let base: Set = ["a", "b", "c", "d", "e"]
        #expect(GridSelection.select(ids: ids, from: 3, to: 1, adding: false, base: base) == ["a", "e"])
    }

    @Test("Dragging back shrinks the range and restores items it leaves")
    func shrinkingRange() {
        let base: Set = ["f"]
        let far = GridSelection.select(ids: ids, from: 0, to: 4, adding: true, base: base)
        let back = GridSelection.select(ids: ids, from: 0, to: 1, adding: true, base: base)
        #expect(far == ["a", "b", "c", "d", "e", "f"])
        #expect(back == ["a", "b", "f"])
    }

    // MARK: - Auto-scroll

    private func scrollStep(_ y: CGFloat) -> CGFloat {
        GridSelection.autoScrollStep(fingerY: y, visibleTop: 172, visibleBottom: 765, edge: 80, maxStep: 18)
    }

    @Test("No auto-scroll while the finger is away from the edges")
    func noScrollInMiddle() {
        #expect(scrollStep(400) == 0)
        #expect(scrollStep(172 + 80) == 0)
        #expect(scrollStep(765 - 80) == 0)
    }

    @Test("Speed ramps up toward the edge and caps at the maximum")
    func rampsAndCaps() {
        #expect(scrollStep(172 + 40) == -9)    // halfway into the top zone
        #expect(scrollStep(172) == -18)        // at the top edge
        #expect(scrollStep(100) == -18)        // above it: capped
        #expect(scrollStep(765 - 40) == 9)     // halfway into the bottom zone
        #expect(scrollStep(765) == 18)
        #expect(scrollStep(860) == 18)         // over the selection bar: capped
    }

    // MARK: - Date range

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ d: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    @Test("A date range includes whole first and last days")
    func dateRangeWholeDays() {
        let items: [(id: String, date: Date?)] = [
            ("before", day(9, hour: 23)), ("startOfFirst", day(10, hour: 0)),
            ("middle", day(11)), ("endOfLast", day(12, hour: 23)), ("after", day(13, hour: 0)),
        ]
        let picked = GridSelection.ids(in: items, from: day(10, hour: 15), to: day(12, hour: 1), calendar: utc)
        #expect(picked == ["startOfFirst", "middle", "endOfLast"])
    }

    @Test("Dates in either order give the same range; undated items are skipped")
    func dateRangeOrderAndUndated() {
        let items: [(id: String, date: Date?)] = [("a", day(10)), ("b", nil), ("c", day(11))]
        let forward = GridSelection.ids(in: items, from: day(10), to: day(11), calendar: utc)
        let backward = GridSelection.ids(in: items, from: day(11), to: day(10), calendar: utc)
        #expect(forward == ["a", "c"])
        #expect(backward == forward)
        #expect(GridSelection.ids(in: items, from: day(20), to: day(21), calendar: utc).isEmpty)
    }
}
