import Photos
import SwiftUI

struct AssetThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let isSelecting: Bool
    let isSelected: Bool
    /// Shown when the grid is sorted by size.
    let sizeText: String?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay { if isSelected { Color.black.opacity(0.3) } }
            .overlay(alignment: .bottomLeading) {
                if let sizeText { Badge(text: sizeText) }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Badge(text: Self.duration(asset.duration), systemImage: "play.fill")
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting { checkmark }
            }
            .contentShape(Rectangle())
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    private var checkmark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Color.accentColor : .clear)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .padding(6)
    }

    private func load() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let side = 200 * displayScale
        requestID = manager.requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func cancel() {
        if let requestID { manager.cancelImageRequest(requestID) }
        requestID = nil
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct Badge: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.6), in: Capsule())
        .padding(4)
    }
}
