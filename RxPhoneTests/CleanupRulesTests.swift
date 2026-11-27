import Foundation
import Testing
@testable import RxPhone

/// Tests for the cleanup page's rules.
@Suite("CleanupRules")
struct CleanupRulesTests {

    @Test("Large videos start at exactly 20 MB")
    func largeVideoThreshold() {
        #expect(!CleanupRules.isLargeVideo(bytes: 19_999_999))
        #expect(CleanupRules.isLargeVideo(bytes: 20_000_000))
        #expect(CleanupRules.isLargeVideo(bytes: 33_000_000))
        #expect(!CleanupRules.isLargeVideo(bytes: 0))
    }

    // MARK: - Which copy to keep

    struct Copy: Equatable {
        let name: String
        var favorite = false
        var date: Date?
    }

    private func keep(_ group: [Copy]) -> [String] {
        CleanupRules.keepFirst(group, isFavorite: \.favorite, created: \.date).map(\.name)
    }

    private let day = 86_400.0

    @Test("Keeps the oldest copy when none is a favorite")
    func keepsOldest() {
        let group = [
            Copy(name: "new", date: Date(timeIntervalSince1970: 3 * day)),
            Copy(name: "old", date: Date(timeIntervalSince1970: 1 * day)),
            Copy(name: "mid", date: Date(timeIntervalSince1970: 2 * day)),
        ]
        #expect(keep(group) == ["old", "mid", "new"])
    }

    @Test("A favorite is kept even if it is not the oldest")
    func keepsFavorite() {
        let group = [
            Copy(name: "old", date: Date(timeIntervalSince1970: 1 * day)),
            Copy(name: "fav", favorite: true, date: Date(timeIntervalSince1970: 5 * day)),
        ]
        #expect(keep(group).first == "fav")
    }

    @Test("Copies without a date go last")
    func undatedLast() {
        let group = [
            Copy(name: "undated", date: nil),
            Copy(name: "dated", date: Date(timeIntervalSince1970: 9 * day)),
        ]
        #expect(keep(group) == ["dated", "undated"])
    }

    // MARK: - Keep at least one per group

    @Test("Any copy can be selected while another stays unselected")
    func canSelectWhileOneRemains() {
        #expect(CleanupRules.canSelect("c", in: ["a", "b", "c"], selection: ["b"]))
        #expect(CleanupRules.canSelect("a", in: ["a", "b"], selection: []))
    }

    @Test("The last unselected copy cannot be selected")
    func cannotSelectLast() {
        #expect(!CleanupRules.canSelect("a", in: ["a", "b", "c"], selection: ["b", "c"]))
        #expect(!CleanupRules.canSelect("a", in: ["a"], selection: []))
    }

    // MARK: - After delete

    @Test("Deleted copies leave their groups, and groups of one disappear")
    func prune() {
        let groups = [["a1", "a2", "a3"], ["b1", "b2"], ["c1", "c2"]]
        let deleted: Set = ["a2", "b2"]
        #expect(CleanupRules.prune(groups) { deleted.contains($0) } == [["a1", "a3"], ["c1", "c2"]])
        #expect(CleanupRules.prune(groups) { _ in false } == groups)
        #expect(CleanupRules.prune(groups) { _ in true }.isEmpty)
    }

    // MARK: - Selection after a rescan

    @Test("A rescan pre-selects copies in new groups and keeps the user's choices")
    func refreshAddsNewGroups() {
        // The user deselected a2 earlier; group b is new from the rescan.
        let groups = [["a1", "a2", "a3"], ["b1", "b2"]]
        let result = CleanupRules.refreshDuplicateSelection(
            groups: groups, selection: ["a3"], seen: ["a1", "a2", "a3"]
        )
        #expect(result == ["a3", "b2"])
    }

    @Test("Deleted copies leave the selection")
    func refreshDropsGone() {
        let result = CleanupRules.refreshDuplicateSelection(
            groups: [["a1", "a2"]], selection: ["a2", "gone"], seen: ["a1", "a2", "gone"]
        )
        #expect(result == ["a2"])
    }

    @Test("A group never ends up fully selected")
    func refreshKeepsOne() {
        // A new, older copy a0 now leads the group; a1 and a2 were selected.
        let result = CleanupRules.refreshDuplicateSelection(
            groups: [["a0", "a1", "a2"]], selection: ["a1", "a2"], seen: ["a1", "a2"]
        )
        #expect(result == ["a1", "a2"])
        let full = CleanupRules.refreshDuplicateSelection(
            groups: [["a1", "a2"]], selection: ["a1", "a2"], seen: ["a1", "a2"]
        )
        #expect(full == ["a2"])
    }

    // MARK: - Library changes after a scan

    @Test("Deleted items are reported so they leave the results")
    func removedItems() {
        let changes = CleanupRules.libraryChanges(scanned: ["a", "b", "c"], current: ["a", "c"])
        #expect(changes.removed == ["b"])
        #expect(!changes.hasNew)
    }

    @Test("New items call for a rescan")
    func newItems() {
        let changes = CleanupRules.libraryChanges(scanned: ["a", "b"], current: ["a", "b", "new"])
        #expect(changes.removed.isEmpty)
        #expect(changes.hasNew)
        let both = CleanupRules.libraryChanges(scanned: ["a", "b"], current: ["a", "new"])
        #expect(both.removed == ["b"])
        #expect(both.hasNew)
    }

    @Test("Reordering or no change does nothing")
    func noChange() {
        let changes = CleanupRules.libraryChanges(scanned: ["a", "b"], current: ["b", "a"])
        #expect(changes.removed.isEmpty)
        #expect(!changes.hasNew)
    }

    @Test("Space freed counts every copy except the one kept")
    func wastedBytes() {
        let sizes = ["keep": 500, "x": 300, "y": 200]
        #expect(CleanupRules.wastedBytes(["keep", "x", "y"]) { Int64(sizes[$0]!) } == 500)
        #expect(CleanupRules.wastedBytes(["keep"]) { Int64(sizes[$0]!) } == 0)
    }
}
