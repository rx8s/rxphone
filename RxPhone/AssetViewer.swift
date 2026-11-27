import AVFoundation
import Photos
import SwiftUI

/// Full-screen pager over the library: swipe between items, pinch/double-tap
/// to zoom photos, play videos, favorite and delete.
struct AssetViewer: View {
    let library: PhotoLibrary

    @Environment(\.dismiss) private var dismiss
    @State private var position: String?
    @State private var showsChrome = true
    @State private var isZoomed = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// Vertical distance of an in-progress swipe-down-to-close.
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: Axis?
    /// Bottom safe-area inset; the pager ignores it, so pages get it passed in.
    @State private var bottomInset: CGFloat = 0

    /// 0 at rest, 1 when dragged far enough to be fully faded.
    private var dragProgress: CGFloat { ViewerMath.dismissProgress(offset: dragOffset) }

    let source: AssetSource
    /// The items to page through, in grid order, read from the library on
    /// every render. A copy held in this view would go stale: a presented
    /// view keeps its first state, so a changed favorite would not show.
    private var assets: [PHAsset] { library.assets(for: source) }

    init(library: PhotoLibrary, source: AssetSource, startID: String) {
        self.library = library
        self.source = source
        _position = State(initialValue: startID)
    }

    private var current: PHAsset? {
        assets.first { $0.localIdentifier == position }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - dragProgress).ignoresSafeArea()
            pager
                .ignoresSafeArea()
                .scaleEffect(1 - dragProgress * 0.25)
                .offset(y: dragOffset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .simultaneousGesture(dismissDrag, including: isZoomed ? .subviews : .all)
        .accessibilityAction(.escape) { dismiss() }
        .overlay(alignment: .top) { if showsChrome && dragOffset == 0 { topBar.transition(.opacity) } }
        .overlay(alignment: .bottom) { if showsChrome && dragOffset == 0 { bottomBar.transition(.opacity) } }
        .statusBarHidden(!showsChrome)
        .preferredColorScheme(.dark)
        .onChange(of: position) { isZoomed = false }
        .task(id: position) {
            if let current { await library.measure([current]) }
        }
        .alert("ทำรายการไม่สำเร็จ", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    AssetPage(
                        asset: asset,
                        isCurrent: asset.localIdentifier == position,
                        isZoomed: $isZoomed,
                        showsControls: showsChrome && dragOffset == 0,
                        // Just above the bottom bar (44 pt buttons).
                        controlsBottom: bottomInset + 52,
                        onTap: { withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() } }
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .scrollDisabled(isZoomed)
    }

    /// Swipe down to close. The axis is locked on the first movement so
    /// horizontal paging in the ScrollView is left alone.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil {
                    let t = value.translation
                    dragAxis = abs(t.height) > abs(t.width) ? .vertical : .horizontal
                }
                guard dragAxis == .vertical else { return }
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .vertical else { return }
                if ViewerMath.shouldDismiss(translationY: value.translation.height,
                                            predictedY: value.predictedEndTranslation.height) {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("ปิด")
            Spacer()
            if let date = current?.creationDate {
                VStack(spacing: 0) {
                    Text(date.formatted(date: .long, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .background {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var bottomBar: some View {
        let isFavorite = current?.isFavorite ?? false
        return HStack {
            Button { Task { await toggleFavorite() } } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isFavorite ? "เลิกชื่นชอบ" : "ชื่นชอบ")
            Spacer()
            Text(infoText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(role: .destructive) { Task { await deleteCurrent() } } label: {
                Image(systemName: "trash")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("ลบ")
        }
        .foregroundStyle(.white)
        .disabled(current == nil || isWorking)
        .padding(.horizontal, 8)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var infoText: String {
        guard let asset = current else { return "" }
        var parts: [String] = []
        if asset.mediaType == .video {
            parts.append(AssetThumbnail.duration(asset.duration))
        } else {
            parts.append("\(asset.pixelWidth)×\(asset.pixelHeight)")
        }
        if let size = library.sizes[asset.localIdentifier] {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private func toggleFavorite() async {
        guard let asset = current else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await library.setFavorite(asset, !asset.isFavorite)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrent() async {
        guard let asset = current,
              let index = assets.firstIndex(of: asset) else { return }
        // Land on the next item, or the previous one when deleting the last.
        let neighbor = ViewerMath.neighbor(afterDeleting: index, in: assets.map(\.localIdentifier))
        isWorking = true
        defer { isWorking = false }
        do {
            try await library.delete([asset])
            if let neighbor { position = neighbor } else { dismiss() }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            // Declined in the system prompt.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Page

private struct AssetPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    @Binding var isZoomed: Bool
    /// Whether the viewer's bars are showing; the video slider follows them.
    let showsControls: Bool
    /// Distance from the bottom edge to place the video slider at.
    let controlsBottom: CGFloat
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    /// Playback position in seconds, updated while playing and while scrubbing.
    @State private var currentTime: Double = 0
    @State private var isScrubbing = false
    @State private var resumeAfterScrub = false
    @State private var timeObserver: Any?
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                } else {
                    ProgressView().tint(.white)
                }
                if asset.mediaType == .video { videoLayer }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) {
                if asset.mediaType == .video && showsControls {
                    scrubber
                        .padding(.horizontal, 16)
                        .padding(.bottom, controlsBottom)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard asset.mediaType == .image else { return }
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 { resetZoom() } else { setScale(2.5) }
                }
            }
            .onTapGesture(count: 1, perform: onTap)
            .gesture(magnify(in: geo.size), including: asset.mediaType == .image ? .all : .subviews)
            .gesture(pan(in: geo.size), including: scale > 1 ? .all : .subviews)
            .onAppear { load(size: geo.size) }
        }
        .onDisappear(perform: unload)
        .onChange(of: isCurrent) {
            if !isCurrent {
                player?.pause()
                isPlaying = false
                resetZoom()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(asset.mediaType == .video ? "วีดีโอ" : "รูปภาพ")
        .accessibilityIdentifier("page-" + asset.localIdentifier)
    }

    // MARK: Video

    @ViewBuilder
    private var videoLayer: some View {
        if let player, isPlaying || player.currentTime() > .zero {
            PlayerLayerView(player: player)
        }
        Button { togglePlayback() } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(.black.opacity(0.45), in: Circle())
        }
        .opacity(isPlaying ? 0 : 1)
        .accessibilityLabel(isPlaying ? "หยุดชั่วคราว" : "เล่น")
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard let item = note.object as? AVPlayerItem, item == player?.currentItem else { return }
            player?.seek(to: .zero)
            currentTime = 0
            isPlaying = false
        }
    }

    /// Drag to jump within the video; shows elapsed and total time.
    private var scrubber: some View {
        let duration = max(asset.duration, 0.1)
        return HStack(spacing: 10) {
            Text(ViewerMath.durationText(min(currentTime, duration)))
            Slider(
                value: Binding(get: { min(currentTime, duration) }, set: { currentTime = $0; seek(to: $0) }),
                in: 0...duration,
                onEditingChanged: scrubbing
            )
            .tint(.white)
            .accessibilityLabel("ตำแหน่งวีดีโอ")
            .accessibilityValue("\(ViewerMath.durationText(currentTime)) จาก \(ViewerMath.durationText(duration))")
            Text(ViewerMath.durationText(duration))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
    }

    /// Pauses while the slider is held and resumes afterwards if it was playing.
    private func scrubbing(_ editing: Bool) {
        if editing {
            resumeAfterScrub = isPlaying
            isScrubbing = true
            player?.pause()
            isPlaying = false
            Task { _ = await preparePlayer() }
            return
        }
        Task {
            guard let player = await preparePlayer() else { isScrubbing = false; return }
            await player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
            isScrubbing = false
            if resumeAfterScrub {
                player.play()
                isPlaying = true
            }
        }
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Creates the player on first use and keeps `currentTime` in step with it.
    private func preparePlayer() async -> AVPlayer? {
        if let player { return player }
        guard let item = await PhotoLibrary.playerItem(for: asset) else { return nil }
        let player = AVPlayer(playerItem: item)
        let isScrubbing = $isScrubbing
        let currentTime = $currentTime
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { time in
            MainActor.assumeIsolated {
                if !isScrubbing.wrappedValue { currentTime.wrappedValue = time.seconds }
            }
        }
        self.player = player
        return player
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        Task {
            guard let player = await preparePlayer() else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player.play()
            isPlaying = true
        }
    }

    // MARK: Zoom

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                setScale(lastScale * value.magnification, in: size)
            }
            .onEnded { _ in
                if scale < 1.05 {
                    withAnimation(.spring(duration: 0.3)) { resetZoom() }
                } else {
                    lastScale = scale
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clamped(
                    CGSize(width: lastOffset.width + value.translation.width,
                           height: lastOffset.height + value.translation.height),
                    in: size
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func setScale(_ value: CGFloat, in size: CGSize? = nil) {
        scale = min(max(value, 1), maxScale)
        lastScale = scale
        if let size { offset = clamped(offset, in: size) }
        isZoomed = scale > 1
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        if isCurrent { isZoomed = false }
    }

    /// Keeps the zoomed image from being dragged past its edges.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let fitted = ViewerMath.fittedSize(
            CGSize(width: asset.pixelWidth, height: asset.pixelHeight), in: size
        )
        return ViewerMath.clampedOffset(proposed, viewSize: size, contentSize: fitted, scale: scale)
    }

    // MARK: Loading

    private func load(size: CGSize) {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        // 2x the screen so zooming in stays sharp without loading full resolution.
        let target = CGSize(width: size.width * displayScale * 2, height: size.height * displayScale * 2)
        requestID = PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFit, options: options
        ) { result, _ in
            if let result { image = result }
        }
    }

    private func unload() {
        if let requestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = nil
        image = nil
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player = nil
        isPlaying = false
        currentTime = 0
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
