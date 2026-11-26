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

    static let largeVideoBytes: Int64 = 20_000_000

    private(set) var state: State = .idle
    /// Each group holds identical photos; the first one is the one to keep.
    private(set) var duplicateGroups: [[PHAsset]] = []
    private(set) var largeVideos: [PHAsset] = []
    private(set) var screenshots: [PHAsset] = []

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

        let shots = all.filter { $0.mediaType == .image && $0.mediaSubtypes.contains(.photoScreenshot) }
        let videos = all.filter { $0.mediaType == .video }
        await library.measure(shots + videos)
        screenshots = shots.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        largeVideos = videos
            .filter { (library.sizes[$0.localIdentifier] ?? 0) >= Self.largeVideoBytes }
            .sorted { (library.sizes[$0.localIdentifier] ?? 0) > (library.sizes[$1.localIdentifier] ?? 0) }

        duplicateGroups = await findDuplicates(in: all.filter { $0.mediaType == .image })
        await library.measure(duplicateGroups.flatMap { $0 })
        duplicateGroups.sort { wasted($0, library) > wasted($1, library) }
        state = .finished
    }

    /// Drops deleted assets from the results.
    func remove(_ ids: Set<String>) {
        duplicateGroups = duplicateGroups
            .map { $0.filter { !ids.contains($0.localIdentifier) } }
            .filter { $0.count > 1 }
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

        var buckets: [String: [(asset: PHAsset, pixels: [UInt8])]] = [:]
        var index = 0
        let chunkSize = 16
        while index < candidates.count {
            let chunk = Array(candidates[index..<min(index + chunkSize, candidates.count)])
            let prints = await Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: (Int, Fingerprint?).self) { group in
                    for (i, asset) in chunk.enumerated() {
                        group.addTask { (i, Self.fingerprint(of: asset)) }
                    }
                    var out = [Fingerprint?](repeating: nil, count: chunk.count)
                    for await (i, print) in group { out[i] = print }
                    return out
                }
            }.value
            for (asset, print) in zip(chunk, prints) {
                guard let print else { continue }
                buckets["\(asset.pixelWidth)x\(asset.pixelHeight)|\(print.hash)", default: []]
                    .append((asset, print.pixels))
            }
            index += chunk.count
            state = .scanning(done: index, total: candidates.count)
        }

        // A matching hash only means "looks alike at 16×16". Confirm pixel by
        // pixel so photos that differ in small details are not grouped.
        var groups: [[PHAsset]] = []
        for bucket in buckets.values where bucket.count > 1 {
            var clusters: [[(asset: PHAsset, pixels: [UInt8])]] = []
            for item in bucket {
                if let i = clusters.firstIndex(where: { Self.isSameImage($0[0].pixels, item.pixels) }) {
                    clusters[i].append(item)
                } else {
                    clusters.append([item])
                }
            }
            groups += clusters.filter { $0.count > 1 }.map { $0.map(\.asset) }
        }

        return groups.map { group in
            // Keep a favorite if there is one, otherwise the oldest copy.
            group.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture)
            }
        }
    }

    private func wasted(_ group: [PHAsset], _ library: PhotoLibrary) -> Int64 {
        group.dropFirst().reduce(0) { $0 + (library.sizes[$1.localIdentifier] ?? 0) }
    }

    private struct Fingerprint {
        /// 256-bit difference hash, used to bucket candidates cheaply.
        let hash: String
        /// 64×64 grayscale pixels, used to confirm a match.
        let pixels: [UInt8]
    }

    private static let compareSide = 64

    /// Same image if almost no pixel differs noticeably: tolerates re-encoding
    /// noise, rejects any real change (≤ 4 of 4096 pixels may differ by > 32).
    nonisolated private static func isSameImage(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        var differing = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > 32 {
            differing += 1
            if differing > 4 { return false }
        }
        return true
    }

    nonisolated private static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    nonisolated private static func fingerprint(of asset: PHAsset) -> Fingerprint? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        var image: UIImage?
        let side = CGFloat(compareSide)
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit, options: options
        ) { result, _ in image = result }
        guard let cgImage = image?.cgImage,
              let small = grayscale(cgImage, width: 17, height: 16),
              let large = grayscale(cgImage, width: compareSide, height: compareSide)
        else { return nil }

        var bits = [UInt64](repeating: 0, count: 4)
        for y in 0..<16 {
            for x in 0..<16 where small[y * 17 + x] < small[y * 17 + x + 1] {
                let bit = y * 16 + x
                bits[bit / 64] |= 1 << UInt64(bit % 64)
            }
        }
        return Fingerprint(hash: bits.map { String($0, radix: 16) }.joined(separator: "-"), pixels: large)
    }
}
