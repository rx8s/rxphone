import Foundation

/// How the device's storage splits into photos, videos, everything else and
/// free space. iOS doesn't tell apps how much other apps use, so "other" is
/// whatever is used but isn't in the photo library.
nonisolated struct StorageBreakdown: Equatable {
    let total: Int64
    let free: Int64
    let photos: Int64
    let videos: Int64

    init(total: Int64, free: Int64, photos: Int64, videos: Int64) {
        self.total = max(0, total)
        self.free = min(max(0, free), self.total)
        let used = self.total - self.free
        // Library sizes count originals kept only in iCloud too, so they can
        // add up to more than is actually used. Scale them down to fit.
        let media = max(0, photos) + max(0, videos)
        if media > used, media > 0 {
            let scale = Double(used) / Double(media)
            self.photos = Int64(Double(max(0, photos)) * scale)
            self.videos = used - self.photos
        } else {
            self.photos = max(0, photos)
            self.videos = max(0, videos)
        }
    }

    var used: Int64 { total - free }
    var other: Int64 { max(0, used - photos - videos) }

    /// Share of the total, 0…1, for drawing the bar.
    func fraction(_ bytes: Int64) -> Double {
        total > 0 ? Double(bytes) / Double(total) : 0
    }

    /// Reads the device's capacity and free space. Free space is what iOS
    /// would make available for something the user asked for, the same
    /// figure the Settings app shows.
    static func deviceCapacity() -> (total: Int64, free: Int64)? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (Int64(total), free)
    }
}
