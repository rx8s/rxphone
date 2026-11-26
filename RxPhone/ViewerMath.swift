import CoreGraphics

/// Pure rules behind the full-screen viewer, kept out of the view so they can
/// be unit tested.
nonisolated enum ViewerMath {
    /// Drag distance (pt) or predicted fling distance that closes the viewer.
    static let dismissDistance: CGFloat = 120
    static let dismissFlingDistance: CGFloat = 400

    /// Where to land after deleting the item at `index`: the next item, or the
    /// previous one when deleting the last, or nil when nothing is left.
    static func neighbor<ID>(afterDeleting index: Int, in ids: [ID]) -> ID? {
        guard ids.indices.contains(index) else { return nil }
        if index + 1 < ids.count { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }

    /// Keeps a zoomed image from being dragged past its edges.
    static func clampedOffset(_ proposed: CGSize, viewSize: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(viewSize.width * (scale - 1) / 2, 0)
        let maxY = max(viewSize.height * (scale - 1) / 2, 0)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// A swipe down closes the viewer if it went far enough or was flung.
    static func shouldDismiss(translationY: CGFloat, predictedY: CGFloat) -> Bool {
        translationY > dismissDistance || predictedY > dismissFlingDistance
    }

    /// 0 at rest, 1 once dragged 400 pt down (fully faded).
    static func dismissProgress(offset: CGFloat) -> CGFloat {
        min(max(offset / 400, 0), 1)
    }

    /// "0:05", "12:34", or "1:02:03" for a video length in seconds.
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
