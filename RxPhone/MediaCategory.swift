import Photos

/// Where a grid's items come from, so the full-screen viewer can reload the
/// same list when the library changes.
nonisolated enum AssetSource: Hashable {
    case library
    case category(MediaCategory)
}

/// Kinds of photos and videos iOS already sorts into smart albums, shown on
/// the หมวดหมู่ tab.
nonisolated enum MediaCategory: String, CaseIterable, Identifiable, Hashable {
    // Photos
    case livePhotos, selfies, screenshots, panoramas, portraits, bursts, raw, animated
    // Videos
    case screenRecordings, slomo, timelapses, cinematic

    var id: Self { self }

    enum Section: CaseIterable {
        case photos, videos

        var title: String {
            switch self {
            case .photos: "รูปภาพ"
            case .videos: "วีดีโอ"
            }
        }
    }

    var section: Section {
        switch self {
        case .livePhotos, .selfies, .screenshots, .panoramas, .portraits, .bursts, .raw, .animated: .photos
        case .screenRecordings, .slomo, .timelapses, .cinematic: .videos
        }
    }

    static func categories(in section: Section) -> [MediaCategory] {
        allCases.filter { $0.section == section }
    }

    var title: String {
        switch self {
        case .livePhotos: "Live Photo"
        case .selfies: "เซลฟี่"
        case .screenshots: "ภาพถ่ายหน้าจอ"
        case .panoramas: "พาโนรามา"
        case .portraits: "ภาพบุคคล"
        case .bursts: "ถ่ายรัว"
        case .raw: "RAW"
        case .animated: "ภาพเคลื่อนไหว"
        case .screenRecordings: "วิดีโอบันทึกหน้าจอ"
        case .slomo: "สโลว์โมชัน"
        case .timelapses: "ไทม์แลปส์"
        case .cinematic: "Cinematic"
        }
    }

    var systemImage: String {
        switch self {
        case .livePhotos: "livephoto"
        case .selfies: "person.crop.square"
        case .screenshots: "camera.viewfinder"
        case .panoramas: "pano"
        case .portraits: "cube"
        case .bursts: "square.stack.3d.down.right"
        case .raw: "r.square"
        case .animated: "square.stack.3d.forward.dottedline"
        case .screenRecordings: "record.circle"
        case .slomo: "slowmo"
        case .timelapses: "timelapse"
        case .cinematic: "video.badge.waveform"
        }
    }

    /// The smart album iOS keeps for this kind of media.
    var smartAlbum: PHAssetCollectionSubtype {
        switch self {
        case .livePhotos: .smartAlbumLivePhotos
        case .selfies: .smartAlbumSelfPortraits
        case .screenshots: .smartAlbumScreenshots
        case .panoramas: .smartAlbumPanoramas
        case .portraits: .smartAlbumDepthEffect
        case .bursts: .smartAlbumBursts
        case .raw: .smartAlbumRAW
        case .animated: .smartAlbumAnimated
        case .screenRecordings: .smartAlbumScreenRecordings
        case .slomo: .smartAlbumSlomoVideos
        case .timelapses: .smartAlbumTimelapses
        case .cinematic: .smartAlbumCinematic
        }
    }
}
