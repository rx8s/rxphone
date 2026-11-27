import Photos
import Testing
@testable import RxPhone

/// Tests for the photo/video filter in the library.
@Suite("MediaFilter")
struct MediaFilterTests {

    @Test("All shows photos and videos only")
    func all() {
        #expect(MediaFilter.all.includes(.image))
        #expect(MediaFilter.all.includes(.video))
        #expect(!MediaFilter.all.includes(.audio))
        #expect(!MediaFilter.all.includes(.unknown))
    }

    @Test("Photos and videos each show their own type")
    func split() {
        #expect(MediaFilter.photos.includes(.image))
        #expect(!MediaFilter.photos.includes(.video))
        #expect(MediaFilter.videos.includes(.video))
        #expect(!MediaFilter.videos.includes(.image))
    }

    @Test("Segment titles")
    func titles() {
        #expect(MediaFilter.allCases.map(\.rawValue) == ["ทั้งหมด", "รูปภาพ", "วีดีโอ"])
    }
}
