import Foundation
import Testing
@testable import RxPhone

/// Tests for remembering duplicate fingerprints between scans.
@Suite("FingerprintStore")
struct FingerprintStoreTests {
    private let print = DuplicateMatcher.Fingerprint(pixels: (0..<4096).map { UInt8($0 % 256) }, mean: 127.5)
    private let monday = Date(timeIntervalSince1970: 1_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_086_400)

    @Test("A stored fingerprint is reused while the photo is unchanged")
    func reuse() {
        var store = FingerprintStore()
        store.set(print, for: "a", modified: monday)
        let found = store.fingerprint(for: "a", modified: monday)
        #expect(found?.pixels == print.pixels)
        #expect(found?.mean == print.mean)
        #expect(store.fingerprint(for: "unknown", modified: monday) == nil)
    }

    @Test("An edited photo (new modification date) is fingerprinted again")
    func editedPhoto() {
        var store = FingerprintStore()
        store.set(print, for: "a", modified: monday)
        #expect(store.fingerprint(for: "a", modified: tuesday) == nil)
        #expect(store.fingerprint(for: "a", modified: nil) == nil)
    }

    @Test("Deleted photos are forgotten")
    func prune() {
        var store = FingerprintStore()
        store.set(print, for: "a", modified: monday)
        store.set(print, for: "b", modified: monday)
        store.prune(keeping: ["b", "c"])
        #expect(store.count == 1)
        #expect(store.fingerprint(for: "a", modified: monday) == nil)
        #expect(store.fingerprint(for: "b", modified: monday) != nil)
    }

    @Test("Saved to disk and read back the same")
    func diskRoundTrip() throws {
        let url = URL.temporaryDirectory.appending(path: "fingerprints-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        var store = FingerprintStore()
        store.set(print, for: "a", modified: monday)
        store.set(print, for: "b", modified: nil)
        try store.save(to: url)

        let loaded = FingerprintStore.load(from: url)
        #expect(loaded.count == 2)
        #expect(loaded.fingerprint(for: "a", modified: monday)?.pixels == print.pixels)
        #expect(loaded.fingerprint(for: "b", modified: nil) != nil)
        // 4096 one-byte pixels per photo, not a large number array.
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size < 2 * 4096 + 2_000)
    }

    @Test("A missing or unreadable file gives an empty store")
    func badFile() throws {
        let missing = URL.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).plist")
        #expect(FingerprintStore.load(from: missing).count == 0)

        let junk = URL.temporaryDirectory.appending(path: "junk-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: junk) }
        try Data("not a plist".utf8).write(to: junk)
        #expect(FingerprintStore.load(from: junk).count == 0)
    }
}
