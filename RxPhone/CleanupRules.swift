import Foundation

/// Pure rules behind the cleanup page, kept free of PhotoKit so they can be
/// unit tested.
nonisolated enum CleanupRules {
    static let largeVideoBytes: Int64 = 20_000_000

    static func isLargeVideo(bytes: Int64) -> Bool {
        bytes >= largeVideoBytes
    }

    /// Orders a duplicate group so the copy to keep comes first: a favorite if
    /// there is one, otherwise the oldest. Items without a date sort last.
    static func keepFirst<T>(_ group: [T], isFavorite: (T) -> Bool, created: (T) -> Date?) -> [T] {
        group.sorted { a, b in
            if isFavorite(a) != isFavorite(b) { return isFavorite(a) }
            return (created(a) ?? .distantFuture) < (created(b) ?? .distantFuture)
        }
    }

    /// Whether `id` may be marked for deletion: a duplicate group must always
    /// keep at least one copy unselected.
    static func canSelect<ID: Hashable>(_ id: ID, in group: [ID], selection: Set<ID>) -> Bool {
        group.contains { $0 != id && !selection.contains($0) }
    }

    /// Removes deleted items from duplicate groups and drops groups that no
    /// longer have a copy to delete.
    static func prune<T>(_ groups: [[T]], removing isDeleted: (T) -> Bool) -> [[T]] {
        groups.map { $0.filter { !isDeleted($0) } }.filter { $0.count > 1 }
    }

    /// Compares the library a scan was based on with the library now: which
    /// scanned items are gone, and whether anything new arrived.
    static func libraryChanges<ID: Hashable>(scanned: Set<ID>, current: Set<ID>) -> (removed: Set<ID>, hasNew: Bool) {
        (scanned.subtracting(current), !current.isSubset(of: scanned))
    }

    /// Bytes freed by deleting every copy in `group` except the first.
    static func wastedBytes<T>(_ group: [T], size: (T) -> Int64) -> Int64 {
        group.dropFirst().reduce(0) { $0 + size($1) }
    }
}
