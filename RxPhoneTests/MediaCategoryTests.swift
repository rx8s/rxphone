import Photos
import Testing
@testable import RxPhone

/// Tests for the หมวดหมู่ tab's category list.
@Suite("MediaCategory")
struct MediaCategoryTests {

    @Test("Every category reads its own smart album")
    func uniqueAlbums() {
        let albums = MediaCategory.allCases.map(\.smartAlbum.rawValue)
        #expect(Set(albums).count == albums.count)
    }

    @Test("The four asked-for categories use the matching iOS albums")
    func requestedCategories() {
        #expect(MediaCategory.livePhotos.smartAlbum == .smartAlbumLivePhotos)
        #expect(MediaCategory.selfies.smartAlbum == .smartAlbumSelfPortraits)
        #expect(MediaCategory.screenshots.smartAlbum == .smartAlbumScreenshots)
        #expect(MediaCategory.screenRecordings.smartAlbum == .smartAlbumScreenRecordings)
    }

    @Test("Sections split photos from videos and cover every category once")
    func sections() {
        let photos = MediaCategory.categories(in: .photos)
        let videos = MediaCategory.categories(in: .videos)
        #expect(photos.count + videos.count == MediaCategory.allCases.count)
        #expect(Set(photos).isDisjoint(with: videos))
        #expect(videos == [.screenRecordings, .slomo, .timelapses, .cinematic])
        #expect(photos.first == .livePhotos)
    }

    @Test("Every category has a Thai or product title and an icon")
    func labels() {
        for category in MediaCategory.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.systemImage.isEmpty)
        }
    }
}
