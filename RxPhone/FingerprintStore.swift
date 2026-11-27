import Foundation

/// Remembers each photo's duplicate fingerprint between scans and launches,
/// so a rescan only loads thumbnails for photos it has not seen (or that were
/// edited since). Loading thumbnails is by far the slowest part of a scan.
///
/// Kept free of PhotoKit so it can be unit tested; the scanner passes in each
/// asset's identifier and modification date.
nonisolated struct FingerprintStore: Codable, Sendable {
    /// Bump when the fingerprint algorithm changes so old files are ignored.
    static let formatVersion = 1

    struct Entry: Codable, Sendable, Equatable {
        /// The asset's modification date when fingerprinted; an edit changes it.
        let modified: Date?
        let pixels: Data
        let mean: Double
    }

    private(set) var version = formatVersion
    private(set) var side = DuplicateMatcher.compareSide
    private(set) var entries: [String: Entry] = [:]

    init() {}

    var count: Int { entries.count }

    /// The stored fingerprint, unless the photo changed since it was taken.
    func fingerprint(for id: String, modified: Date?) -> DuplicateMatcher.Fingerprint? {
        guard let entry = entries[id], entry.modified == modified else { return nil }
        return DuplicateMatcher.Fingerprint(pixels: [UInt8](entry.pixels), mean: entry.mean)
    }

    mutating func set(_ print: DuplicateMatcher.Fingerprint, for id: String, modified: Date?) {
        entries[id] = Entry(modified: modified, pixels: Data(print.pixels), mean: print.mean)
    }

    /// Forgets photos that are no longer in the library.
    mutating func prune(keeping ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    // MARK: - Disk

    /// In Caches: iOS may clear it when space is low, which only costs a
    /// slower next scan.
    static var defaultURL: URL {
        URL.cachesDirectory.appending(path: "duplicate-fingerprints.plist")
    }

    /// The saved store, or an empty one when there is none or it is from an
    /// older format.
    static func load(from url: URL = defaultURL) -> FingerprintStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? PropertyListDecoder().decode(FingerprintStore.self, from: data),
              store.version == formatVersion, store.side == DuplicateMatcher.compareSide
        else { return FingerprintStore() }
        return store
    }

    func save(to url: URL = defaultURL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
