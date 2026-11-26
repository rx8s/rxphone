import CoreGraphics
import Testing
@testable import RxPhone

/// Tests for the full-screen viewer's rules.
@Suite("ViewerMath")
struct ViewerMathTests {

    // MARK: - After delete

    @Test("Deleting moves to the next item, or the previous one at the end")
    func neighbor() {
        let ids = ["a", "b", "c"]
        #expect(ViewerMath.neighbor(afterDeleting: 0, in: ids) == "b")
        #expect(ViewerMath.neighbor(afterDeleting: 1, in: ids) == "c")
        #expect(ViewerMath.neighbor(afterDeleting: 2, in: ids) == "b")
    }

    @Test("Deleting the only item closes the viewer")
    func lastItem() {
        #expect(ViewerMath.neighbor(afterDeleting: 0, in: ["a"]) == nil)
        #expect(ViewerMath.neighbor(afterDeleting: 0, in: [String]()) == nil)
        #expect(ViewerMath.neighbor(afterDeleting: 5, in: ["a", "b"]) == nil)
    }

    // MARK: - Zoom panning

    let view = CGSize(width: 400, height: 800)

    @Test("Without zoom the image cannot be moved")
    func noZoom() {
        #expect(ViewerMath.clampedOffset(CGSize(width: 50, height: -80), viewSize: view, scale: 1) == .zero)
    }

    @Test("At 2× the image pans up to half the view in each direction")
    func zoomedPan() {
        #expect(ViewerMath.clampedOffset(CGSize(width: 120, height: -300), viewSize: view, scale: 2)
                == CGSize(width: 120, height: -300))
        #expect(ViewerMath.clampedOffset(CGSize(width: 999, height: -999), viewSize: view, scale: 2)
                == CGSize(width: 200, height: -400))
        // At 4× the limits are ±600 × ±1200: only the horizontal value is cut.
        #expect(ViewerMath.clampedOffset(CGSize(width: -999, height: 999), viewSize: view, scale: 4)
                == CGSize(width: -600, height: 999))
    }

    // MARK: - Swipe down to close

    @Test("Closes after a long enough drag or a fast fling, not a short drag")
    func dismiss() {
        #expect(ViewerMath.shouldDismiss(translationY: 121, predictedY: 0))
        #expect(ViewerMath.shouldDismiss(translationY: 60, predictedY: 401))
        #expect(!ViewerMath.shouldDismiss(translationY: 60, predictedY: 300))
        #expect(!ViewerMath.shouldDismiss(translationY: 120, predictedY: 400))
        #expect(!ViewerMath.shouldDismiss(translationY: -200, predictedY: -500))
    }

    @Test("The fade follows the drag and stays between 0 and 1")
    func progress() {
        #expect(ViewerMath.dismissProgress(offset: 0) == 0)
        #expect(ViewerMath.dismissProgress(offset: 200) == 0.5)
        #expect(ViewerMath.dismissProgress(offset: 900) == 1)
        #expect(ViewerMath.dismissProgress(offset: -50) == 0)
    }

    // MARK: - Video length

    @Test("Video length text", arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (5.4, "0:05"),
        (59.6, "1:00"),
        (65.0, "1:05"),
        (600.0, "10:00"),
        (3599.0, "59:59"),
        (3723.0, "1:02:03"),
    ])
    func duration(seconds: Double, expected: String) {
        #expect(ViewerMath.durationText(seconds) == expected)
    }
}
