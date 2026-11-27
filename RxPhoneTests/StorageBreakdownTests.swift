import Testing
@testable import RxPhone

@Suite("StorageBreakdown")
struct StorageBreakdownTests {

    @Test("Other is what's used but not in the library")
    func otherIsTheRest() {
        let b = StorageBreakdown(total: 128, free: 28, photos: 30, videos: 20)
        #expect(b.used == 100)
        #expect(b.other == 50)
        #expect(b.photos + b.videos + b.other + b.free == b.total)
    }

    @Test("Library bigger than used space (iCloud originals) is scaled to fit")
    func scalesWhenLibraryExceedsUsed() {
        let b = StorageBreakdown(total: 100, free: 60, photos: 60, videos: 20)
        #expect(b.photos == 30)
        #expect(b.videos == 10)
        #expect(b.other == 0)
        #expect(b.photos + b.videos + b.other + b.free == b.total)
    }

    @Test("Bad inputs are clamped")
    func clamps() {
        let b = StorageBreakdown(total: 50, free: 80, photos: -5, videos: 0)
        #expect(b.free == 50)
        #expect(b.used == 0)
        #expect(b.photos == 0)
        #expect(b.other == 0)
        #expect(StorageBreakdown(total: 0, free: 0, photos: 0, videos: 0).fraction(0) == 0)
    }

    @Test("Fraction is a share of the total")
    func fraction() {
        let b = StorageBreakdown(total: 200, free: 50, photos: 50, videos: 0)
        #expect(b.fraction(50) == 0.25)
    }
}
