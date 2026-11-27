import Observation
import Photos
import UIKit

enum CleanupCategory: Hashable, CaseIterable {
    case duplicates, largeVideos, screenshots

    var title: String {
        switch self {
        case .duplicates: "รูปซ้ำ"
        case .largeVideos: "วีดีโอขนาดใหญ่"
        case .screenshots: "ภาพหน้าจอ"
        }
    }

    var subtitle: String {
        switch self {
        case .duplicates: "รูปเดียวกันที่บันทึกไว้มากกว่า 1 ครั้ง"
        case .largeVideos: "วีดีโอตั้งแต่ 20 MB ขึ้นไป"
        case .screenshots: "ภาพที่แคปหน้าจอไว้"
        }
    }

    var systemImage: String {
        switch self {
        case .duplicates: "square.on.square"
        case .largeVideos: "film"
        case .screenshots: "camera.viewfinder"
        }
    }
}

/// Finds cleanup candidates in the library: exact duplicate photos, videos of
/// 20 MB or more, and screenshots.
@Observable
final class CleanupScanner {
    enum State: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case finished
    }

    private(set) var state: State = .idle
    /// Each group holds identical photos; the first one is the one to keep.
    private(set) var duplicateGroups: [[PHAsset]] = []
    private(set) var largeVideos: [PHAsset] = []
    private(set) var screenshots: [PHAsset] = []
    /// Photos left out of the duplicate check because their thumbnail is only
    /// in iCloud. The scan never downloads, to save data.
    private(set) var skippedInCloud = 0
    /// Library items the last scan looked at, to tell later what changed.
    @ObservationIgnored private var scannedIDs: Set<String> = []

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    func assets(in category: CleanupCategory) -> [PHAsset] {
        switch category {
        case .duplicates: duplicateGroups.flatMap { $0.dropFirst() }
        case .largeVideos: largeVideos
        case .screenshots: screenshots
        }
    }

    func scan(_ library: PhotoLibrary) async {
        guard !isScanning else { return }
        state = .scanning(done: 0, total: 0)
        let all = library.assets
        scannedIDs = Set(all.map(\.localIdentifier))

        // Same source as the หมวดหมู่ tab, so both pages count the same screenshots.
        let shots = library.assets(in: .screenshots)
        let videos = all.filter { $0.mediaType == .video }
        await library.measure(shots + videos)
        screenshots = shots.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        largeVideos = videos
            .filter { CleanupRules.isLargeVideo(bytes: library.sizes[$0.localIdentifier] ?? 0) }
            .sorted { (library.sizes[$0.localIdentifier] ?? 0) > (library.sizes[$1.localIdentifier] ?? 0) }

        duplicateGroups = await findDuplicates(in: all.filter { $0.mediaType == .image })
        await library.measure(duplicateGroups.flatMap { $0 })
        duplicateGroups.sort { wasted($0, library) > wasted($1, library) }
        state = .finished
    }

    /// Brings results in line with the library after it changed: deleted
    /// items drop out right away; new items trigger a rescan after `delay`.
    /// Called from a task that restarts on every change, so a burst of
    /// changes waits out the delay once and scans once.
    func sync(with library: PhotoLibrary, delay: Duration = .seconds(2)) async {
        guard state == .finished else { return }
        let current = Set(library.assets.map(\.localIdentifier))
        let changes = CleanupRules.libraryChanges(scanned: scannedIDs, current: current)
        if !changes.removed.isEmpty {
            remove(changes.removed)
            scannedIDs.subtract(changes.removed)
        }
        guard changes.hasNew else { return }
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        await scan(library)
    }

    /// Drops deleted assets from the results.
    func remove(_ ids: Set<String>) {
        duplicateGroups = CleanupRules.prune(duplicateGroups) { ids.contains($0.localIdentifier) }
        largeVideos.removeAll { ids.contains($0.localIdentifier) }
        screenshots.removeAll { ids.contains($0.localIdentifier) }
    }

    // MARK: - Duplicates

    /// Exact copies share pixel dimensions, so only photos with a size twin are
    /// fingerprinted. Within each size, identical fingerprints form a group.
    private func findDuplicates(in images: [PHAsset]) async -> [[PHAsset]] {
        let candidates = Dictionary(grouping: images) { "\($0.pixelWidth)x\($0.pixelHeight)" }
            .values.filter { $0.count > 1 }.flatMap { $0 }
        state = .scanning(done: 0, total: candidates.count)

        var fingerprinted: [(asset: PHAsset, print: DuplicateMatcher.Fingerprint)] = []
        var skipped = 0
        var index = 0
        let chunkSize = 16
        while index < candidates.count {
            let chunk = Array(candidates[index..<min(index + chunkSize, candidates.count)])
            let prints = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: (Int, DuplicateMatcher.Fingerprint?).self) { group in
                    for (i, asset) in chunk.enumerated() {
                        group.addTask { (i, Self.fingerprint(of: asset)) }
                    }
                    var out = [DuplicateMatcher.Fingerprint?](repeating: nil, count: chunk.count)
                    for await (i, print) in group { out[i] = print }
                    return out
                }
            }.value
            for (asset, print) in zip(chunk, prints) {
                if let print { fingerprinted.append((asset, print)) } else { skipped += 1 }
            }
            index += chunk.count
            state = .scanning(done: index, total: candidates.count)
        }
        skippedInCloud = skipped

        let groups = DuplicateMatcher.groups(fingerprinted.enumerated().map {
            (id: $0.offset, width: $0.element.asset.pixelWidth,
             height: $0.element.asset.pixelHeight, print: $0.element.print)
        }).map { $0.map { fingerprinted[$0].asset } }

        return groups.map { group in
            CleanupRules.keepFirst(group, isFavorite: \.isFavorite, created: \.creationDate)
        }
    }

    private func wasted(_ group: [PHAsset], _ library: PhotoLibrary) -> Int64 {
        CleanupRules.wastedBytes(group) { library.sizes[$0.localIdentifier] ?? 0 }
    }

    /// Fingerprints a small thumbnail already on the device. Returns nil when
    /// the photo is only in iCloud: downloading would use mobile data.
    nonisolated private static func fingerprint(of asset: PHAsset) -> DuplicateMatcher.Fingerprint? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var image: UIImage?
        let side = CGFloat(DuplicateMatcher.compareSide)
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit, options: options
        ) { result, _ in image = result }
        guard let cgImage = image?.cgImage else { return nil }
        return DuplicateMatcher.fingerprint(of: cgImage)
    }
}
