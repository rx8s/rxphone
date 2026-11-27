import XCTest

/// End-to-end checks that drive the real app in the Simulator.
///
/// They need photo access and at least 3 photos in the Simulator's library,
/// plus at least one exact duplicate for the cleanup test. Delete steps always
/// tap "Don't Allow" in the system prompt, so the library is never changed.
@MainActor
final class RxPhoneUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Launch arguments override saved choices, so every test starts from
        // the defaults whatever the previous test left behind.
        app.launchArguments = Self.defaults
        app.launch()
        grantAccessIfNeeded()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "No photos in the library")
    }

    private static let defaults = ["-mediaFilter", "all", "-sortOrder", "newest"]

    /// Taps a filter back to ทั้งหมด. The app saves the choice, so tests that
    /// change it put it back and leave the Simulator as they found it.
    private func resetFilter() {
        let all = segment("ทั้งหมด")
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: all)
        waitForExpectations(timeout: 5)
    }

    // MARK: - Helpers

    private var cells: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'cell-'"))
    }

    private var firstCell: XCUIElement { cells.element(boundBy: 0) }

    private var selectionCount: XCUIElement { app.staticTexts["selection-count"] }

    /// Taps through the permission screen and the system prompt on a fresh install.
    private func grantAccessIfNeeded() {
        let allow = app.buttons["อนุญาตการเข้าถึง"]
        guard allow.waitForExistence(timeout: 3) else { return }
        allow.tap()
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let full = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Access'")).firstMatch
            (full.exists ? full : alert.buttons.element(boundBy: alert.buttons.count - 1)).tap()
        }
    }

    /// The system's "Allow RxPhone to delete…?" prompt, wherever iOS shows it.
    private func deletePrompt() -> XCUIElement? {
        for alert in [app.alerts.firstMatch, springboard.alerts.firstMatch] where alert.waitForExistence(timeout: 5) {
            return alert
        }
        return nil
    }

    private func declineDelete() {
        guard let alert = deletePrompt() else { return XCTFail("Delete prompt did not appear") }
        let decline = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' AND NOT (label BEGINSWITH[c] 'Allow')")).firstMatch
        (decline.exists ? decline : alert.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    private func enterSelectMode() {
        app.navigationBars.buttons["เลือก"].tap()
        XCTAssertTrue(selectionCount.waitForExistence(timeout: 3))
        XCTAssertEqual(selectionCount.label, "เลือก 0 รายการ")
    }

    private func openViewer(on cell: XCUIElement) -> XCUIElement {
        let id = cell.identifier.replacingOccurrences(of: "cell-", with: "")
        cell.tap()
        let page = app.descendants(matching: .any)["page-" + id]
        XCTAssertTrue(page.waitForExistence(timeout: 5), "Viewer did not open on the tapped item")
        // Taps during the slide-up animation are dropped, so wait until the
        // viewer has settled at the top of the screen.
        let settled = NSPredicate { _, _ in page.frame.minY.magnitude < 1 }
        expectation(for: settled, evaluatedWith: page)
        waitForExpectations(timeout: 5)
        return page
    }

    // MARK: - Library

    func testLibraryShowsGridAndTabs() {
        XCTAssertTrue(app.navigationBars["คลัง"].exists)
        XCTAssertTrue(app.tabBars.buttons["คลัง"].exists)
        XCTAssertTrue(app.tabBars.buttons["ทำความสะอาด"].exists)
        XCTAssertGreaterThanOrEqual(cells.count, 3)
    }

    func testSortMenuReordersGrid() {
        let newestFirst = firstCell.identifier
        app.navigationBars.buttons["เรียงตาม"].tap()
        app.buttons["เก่าสุดก่อน"].tap()
        let predicate = NSPredicate(format: "identifier != %@", newestFirst)
        expectation(for: predicate, evaluatedWith: firstCell)
        waitForExpectations(timeout: 5)

        app.navigationBars.buttons["เรียงตาม"].tap()
        app.buttons["ใหม่สุดก่อน"].tap()
        expectation(for: NSPredicate(format: "identifier == %@", newestFirst), evaluatedWith: firstCell)
        waitForExpectations(timeout: 5)
    }

    func testTapToSelectAndDone() {
        enterSelectMode()
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        XCTAssertEqual(selectionCount.label, "เลือก 2 รายการ")
        cells.element(boundBy: 0).tap()
        XCTAssertEqual(selectionCount.label, "เลือก 1 รายการ")

        app.navigationBars.buttons["เสร็จ"].tap()
        XCTAssertTrue(selectionCount.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.buttons["เลือก"].exists)
    }

    func testDragAcrossRowSelectsRange() {
        enterSelectMode()
        let start = cells.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = cells.element(boundBy: 2).coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(selectionCount.label, "เลือก 3 รายการ")
    }

    func testDeleteFromGridCanBeCancelled() {
        // The grid is lazy, so count from the filter title, not the cells.
        let count = segment("ทั้งหมด").label
        enterSelectMode()
        firstCell.tap()
        app.buttons["ลบ"].tap()
        declineDelete()
        // Declining keeps the photo and the selection.
        XCTAssertEqual(segment("ทั้งหมด").label, count)
        XCTAssertEqual(selectionCount.label, "เลือก 1 รายการ")
    }

    // MARK: - Photo / video filter

    private func segment(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + " (")).firstMatch
    }

    /// The number in a segment title such as "วีดีโอ (2)".
    private func count(in segment: XCUIElement) -> Int {
        Int(segment.label.split(separator: "(").last!.dropLast()) ?? -1
    }

    func testFilterShowsOnlyVideosThenOnlyPhotos() {
        let all = count(in: segment("ทั้งหมด"))
        let videos = count(in: segment("วีดีโอ"))
        let photos = count(in: segment("รูปภาพ"))
        XCTAssertEqual(all, videos + photos)
        XCTAssertGreaterThan(videos, 0, "Needs at least one video in the library")

        segment("วีดีโอ").tap()
        expectation(for: NSPredicate(format: "count == %d", videos), evaluatedWith: cells)
        waitForExpectations(timeout: 5)
        for cell in cells.allElementsBoundByIndex {
            XCTAssertTrue(cell.label.hasPrefix("วีดีโอ"), "Non-video shown: \(cell.label)")
        }

        segment("รูปภาพ").tap()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        XCTAssertTrue(firstCell.label.hasPrefix("รูปภาพ"))
        XCTAssertFalse(cells.allElementsBoundByIndex.contains { $0.label.hasPrefix("วีดีโอ") })

        segment("ทั้งหมด").tap()
        // The grid is lazy: only on-screen cells exist, so check for a mix.
        let video = cells.matching(NSPredicate(format: "label BEGINSWITH 'วีดีโอ'")).firstMatch
        let photo = cells.matching(NSPredicate(format: "label BEGINSWITH 'รูปภาพ'")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertTrue(photo.exists)
    }

    func testViewerPagesOnlyWithinFilter() {
        segment("วีดีโอ").tap()
        let last = cells.element(boundBy: cells.count - 1)
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        let page = openViewer(on: last)
        // Swiping past the last video must not reveal a photo.
        page.swipeLeft()
        XCTAssertTrue(page.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'page-' AND label == 'รูปภาพ'"))
            .firstMatch.exists)
        app.buttons["ปิด"].tap()
        resetFilter()
    }

    func testSwitchingFilterDropsHiddenSelection() {
        enterSelectMode()
        segment("รูปภาพ").tap()
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()
        XCTAssertEqual(selectionCount.label, "เลือก 1 รายการ")
        // The selected photo is hidden under วีดีโอ, so it must not stay selected
        // and be deleted unseen.
        segment("วีดีโอ").tap()
        XCTAssertEqual(selectionCount.label, "เลือก 0 รายการ")
        resetFilter()
    }

    func testFilterAndSortAreRememberedAfterRelaunch() {
        segment("วีดีโอ").tap()
        app.navigationBars.buttons["เรียงตาม"].tap()
        app.buttons["เก่าสุดก่อน"].tap()

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(segment("วีดีโอ").waitForExistence(timeout: 10))
        XCTAssertTrue(segment("วีดีโอ").isSelected, "Filter was not remembered")
        app.navigationBars.buttons["เรียงตาม"].tap()
        XCTAssertTrue(app.buttons["เก่าสุดก่อน"].isSelected, "Sort order was not remembered")

        // Leave the saved choices at their defaults.
        app.buttons["ใหม่สุดก่อน"].tap()
        resetFilter()
    }

    // MARK: - Categories

    func testCategoriesTabListsKindsAndOpensOne() throws {
        app.tabBars.buttons["หมวดหมู่"].tap()
        XCTAssertTrue(app.navigationBars["หมวดหมู่"].waitForExistence(timeout: 5))
        func row(_ id: String) -> XCUIElement { app.descendants(matching: .any)["category-" + id] }
        for id in ["livePhotos", "selfies", "screenshots"] {
            XCTAssertTrue(row(id).waitForExistence(timeout: 5), "Missing category \(id)")
        }
        // The list loads rows as they scroll in; the videos section is lower.
        app.swipeUp()
        XCTAssertTrue(row("screenRecordings").waitForExistence(timeout: 5), "Missing screen recordings")
        app.swipeDown()

        // Open the first category that has items, if the Simulator has any.
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'category-' AND isEnabled == true"))
        guard rows.count > 0 else { throw XCTSkip("No category has items in this Simulator") }
        let row = rows.element(boundBy: 0)
        let title = row.label
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5), "Category grid is empty")
        XCTAssertTrue(app.navigationBars.buttons["เลือก"].isEnabled)
        // No library-wide controls inside a category.
        XCTAssertFalse(app.navigationBars.buttons["เรียงตาม"].exists)
        XCTAssertFalse(segment("ทั้งหมด").exists)
    }

    // MARK: - Viewer

    func testViewerPagesAndCloses() {
        let first = openViewer(on: firstCell)
        let secondID = cells.element(boundBy: 1).identifier.replacingOccurrences(of: "cell-", with: "")
        first.swipeLeft()
        let second = app.descendants(matching: .any)["page-" + secondID]
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        XCTAssertTrue(second.isHittable, "Swiping left should show the next item")

        app.buttons["ปิด"].tap()
        XCTAssertTrue(app.buttons["ปิด"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["คลัง"].exists)
    }

    func testSwipeDownClosesViewer() {
        let page = openViewer(on: firstCell)
        let top = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 400)))
        XCTAssertTrue(app.buttons["ปิด"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["คลัง"].exists)
    }

    func testFavoriteToggles() {
        _ = openViewer(on: firstCell)
        let favorite = app.buttons["ชื่นชอบ"]
        let unfavorite = app.buttons["เลิกชื่นชอบ"]
        let wasFavorite = unfavorite.exists
        (wasFavorite ? unfavorite : favorite).tap()
        XCTAssertTrue((wasFavorite ? favorite : unfavorite).waitForExistence(timeout: 5))
        // Put it back the way it was. The button stays disabled until the
        // first change finishes saving, so wait for it.
        let restore = wasFavorite ? favorite : unfavorite
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: restore)
        waitForExpectations(timeout: 5)
        restore.tap()
        XCTAssertTrue((wasFavorite ? unfavorite : favorite).waitForExistence(timeout: 5))
    }

    func testDeleteFromViewerCanBeCancelled() {
        let page = openViewer(on: firstCell)
        app.buttons["ลบ"].tap()
        declineDelete()
        XCTAssertTrue(page.exists, "Declining should keep the item on screen")
    }

    // MARK: - Cleanup

    func testCleanupFindsDuplicatesAndKeepsOne() {
        app.tabBars.buttons["ทำความสะอาด"].tap()
        let summary = app.staticTexts["ลบได้สูงสุด"]
        XCTAssertTrue(summary.waitForExistence(timeout: 60), "Scan did not finish")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'รูปซ้ำ'")).firstMatch.tap()
        XCTAssertTrue(selectionCount.waitForExistence(timeout: 3))
        XCTAssertNotEqual(selectionCount.label, "เลือก 0 รายการ", "Duplicates should start selected")

        // The copy marked "keep" is the last unselected one in its group.
        let kept = app.descendants(matching: .any).matching(NSPredicate(format: "value == 'เก็บไว้'")).firstMatch
        XCTAssertTrue(kept.exists)
        let before = selectionCount.label
        kept.tap()
        XCTAssertTrue(app.staticTexts["ต้องเก็บไว้อย่างน้อย 1 รูปในแต่ละกลุ่ม"].waitForExistence(timeout: 3))
        XCTAssertEqual(selectionCount.label, before)

        app.buttons["ไม่เลือก"].tap()
        XCTAssertEqual(selectionCount.label, "เลือก 0 รายการ")
    }
}
