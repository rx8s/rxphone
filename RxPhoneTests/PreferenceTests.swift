import Testing
@testable import RxPhone

/// Tests for remembering the sort order and photo/video filter.
@Suite("Preference")
struct PreferenceTests {

    @Test("Choices are stored by case name and read back")
    func roundTrip() {
        for order in SortOrder.allCases {
            #expect(Preference.decode(Preference.encode(order), default: SortOrder.newest) == order)
        }
        for filter in MediaFilter.allCases {
            #expect(Preference.decode(Preference.encode(filter), default: MediaFilter.all) == filter)
        }
        #expect(Preference.encode(MediaFilter.videos) == "videos")
    }

    @Test("Nothing saved, or an unknown value, falls back to the default")
    func fallback() {
        #expect(Preference.decode(nil, default: SortOrder.newest) == .newest)
        #expect(Preference.decode("removedCase", default: MediaFilter.all) == .all)
        // The Thai title is not the stored value.
        #expect(Preference.decode("วีดีโอ", default: MediaFilter.all) == .all)
    }
}
