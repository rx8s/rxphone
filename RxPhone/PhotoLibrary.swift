import Observation
import Photos

enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "ใหม่สุดก่อน"
    case oldest = "เก่าสุดก่อน"
    case largest = "ไฟล์ใหญ่สุดก่อน"

    var id: Self { self }
}

/// Wraps PhotoKit: permission, fetching photos/videos, file sizes and deletion.
@Observable
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var assets: [PHAsset] = []
    private(set) var isLoaded = false
    private(set) var isMeasuring = false
    /// File size in bytes, keyed by `PHAsset.localIdentifier`.
    private(set) var sizes: [String: Int64] = [:]

    var sortOrder: SortOrder = .newest {
        didSet { Task { await reload() } }
    }

    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private var fetchResult: PHFetchResult<PHAsset>?
    @ObservationIgnored private var isObserving = false

    var hasAccess: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await start()
    }

    func start() async {
        guard hasAccess else { return }
        if !isObserving {
            PHPhotoLibrary.shared().register(self)
            isObserving = true
        }
        await reload()
    }

    func reload() async {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d || mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: sortOrder == .oldest)
        ]
        let result = PHAsset.fetchAssets(with: options)
        fetchResult = result

        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }

        if sortOrder == .largest {
            await measure(list)
            list.sort { (sizes[$0.localIdentifier] ?? 0) > (sizes[$1.localIdentifier] ?? 0) }
        }
        assets = list
        isLoaded = true
    }

    /// Computes file sizes for assets not measured yet, off the main thread.
    func measure(_ list: [PHAsset]) async {
        let missing = list.filter { sizes[$0.localIdentifier] == nil }
        guard !missing.isEmpty else { return }
        isMeasuring = true
        let found = await Task.detached(priority: .userInitiated) {
            var out: [String: Int64] = [:]
            for asset in missing { out[asset.localIdentifier] = Self.fileSize(of: asset) }
            return out
        }.value
        sizes.merge(found) { $1 }
        isMeasuring = false
    }

    /// Moves the assets to "Recently Deleted". iOS shows its own confirmation;
    /// throws `PHPhotosError.userCancelled` if the user declines.
    func delete(_ targets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges(Self.deleteRequest(targets))
    }

    nonisolated private static func deleteRequest(_ targets: [PHAsset]) -> @Sendable () -> Void {
        { PHAssetChangeRequest.deleteAssets(targets as NSArray) }
    }

    /// Sum of the asset's resources (original + edits). PhotoKit has no public
    /// size API; `fileSize` on PHAssetResource is the commonly used KVC key.
    nonisolated private static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(0) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? CLong).map(Int64.init) ?? 0)
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            if let result = self.fetchResult, changeInstance.changeDetails(for: result) == nil { return }
            self.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            await self.reload()
        }
    }
}
