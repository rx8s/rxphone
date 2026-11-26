import CoreGraphics

/// Exact-duplicate matching on plain images, kept free of PhotoKit so it can
/// be unit tested. `CleanupScanner` feeds it thumbnails from the library.
nonisolated enum DuplicateMatcher {
    struct Fingerprint: Sendable {
        /// 64×64 grayscale pixels, compared pixel by pixel to confirm a match.
        let pixels: [UInt8]
        /// Average gray level, used to find candidates without comparing every pair.
        let mean: Double
    }

    static let compareSide = 64
    /// A pixel "differs" when its gray level changes by more than this.
    static let pixelTolerance = 32
    /// How many differing pixels (of 4096) still count as the same image.
    static let maxDifferingPixels = 4
    /// Copies (even re-saved as JPEG) have almost the same average brightness;
    /// only pairs this close are compared pixel by pixel.
    static let meanTolerance = 2.0

    static func fingerprint(of image: CGImage) -> Fingerprint? {
        guard let pixels = grayscale(image, width: compareSide, height: compareSide) else { return nil }
        let mean = Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
        return Fingerprint(pixels: pixels, mean: mean)
    }

    /// Same image if almost no pixel differs noticeably: tolerates re-encoding
    /// noise, rejects any real change.
    static func isSameImage(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var differing = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > pixelTolerance {
            differing += 1
            if differing > maxDifferingPixels { return false }
        }
        return true
    }

    /// Groups items that share pixel dimensions and match pixel by pixel.
    /// Within each size, items are sorted by average brightness and only
    /// neighbors within `meanTolerance` are compared, so the work stays close
    /// to linear. Returns only groups of two or more, in input order.
    static func groups<ID>(_ items: [(id: ID, width: Int, height: Int, print: Fingerprint)]) -> [[ID]] {
        var parent = Array(items.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }

        let bySize = Dictionary(grouping: items.indices) { "\(items[$0].width)x\(items[$0].height)" }
        for indices in bySize.values where indices.count > 1 {
            let sorted = indices.sorted { items[$0].print.mean < items[$1].print.mean }
            for (n, i) in sorted.enumerated() {
                for j in sorted[(n + 1)...] {
                    if items[j].print.mean - items[i].print.mean > meanTolerance { break }
                    if root(i) != root(j),
                       isSameImage(items[i].print.pixels, items[j].print.pixels) {
                        parent[root(j)] = root(i)
                    }
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for i in items.indices { members[root(i), default: []].append(i) }
        return members.values
            .filter { $0.count > 1 }
            .sorted { $0[0] < $1[0] }
            .map { $0.map { items[$0].id } }
    }

    static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
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
}
