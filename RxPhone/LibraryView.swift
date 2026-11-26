import Photos
import PhotosUI
import SwiftUI

struct LibraryView: View {
    @Bindable var library: PhotoLibrary
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isDeleting = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var viewer: ViewerTarget?

    private struct ViewerTarget: Identifiable { let id: String }

    /// State of a finger dragging across the grid in selection mode.
    private struct DragSelect {
        let startIndex: Int
        /// Select or deselect, decided by the cell the drag started on.
        let adding: Bool
        /// Selection before the drag, so cells that leave the range revert.
        let base: Set<String>
    }

    /// What auto-scroll needs to know about the ScrollView, in points.
    private struct ScrollMetrics: Equatable {
        /// Content offset; `-insetTop` when scrolled to the very top.
        var offset: CGFloat = 0
        var insetTop: CGFloat = 0
        var maxOffset: CGFloat = 0
    }

    @State private var dragSelect: DragSelect?
    /// Finger position in screen coordinates while drag-selecting.
    @State private var fingerLocation: CGPoint?
    /// Grid frame in screen coordinates; moves as the content scrolls.
    @State private var gridFrame: CGRect = .zero
    /// ScrollView frame and the selection bar's top edge, in screen coordinates.
    @State private var scrollFrame: CGRect = .zero
    @State private var selectionBarTop: CGFloat?
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollMetrics = ScrollMetrics()
    /// Distance from the top/bottom edge where auto-scroll kicks in.
    private static let autoScrollEdge: CGFloat = 80
    /// Fastest auto-scroll speed, reached at the very edge (points per frame).
    private static let autoScrollMaxStep: CGFloat = 18

    private static let cellMinSize: CGFloat = 100
    private static let cellSpacing: CGFloat = 2
    private let columns = [GridItem(.adaptive(minimum: cellMinSize), spacing: cellSpacing)]

    var body: some View {
        NavigationStack {
            grid
                .navigationTitle("คลัง")
                .toolbar { toolbar }
        }
        .fullScreenCover(item: $viewer) { target in
            AssetViewer(library: library, startID: target.id)
                // Lets the grid show through while swiping down to close.
                .presentationBackground(.clear)
        }
        .alert("ลบไม่สำเร็จ", isPresented: .constant(errorMessage != nil)) {
            Button("ตกลง") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Content

    private var grid: some View {
        ScrollView {
            if library.status == .limited { limitedBanner }
            LazyVGrid(columns: columns, spacing: Self.cellSpacing) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    cell(for: asset)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { gridFrame = $0 }
            .gesture(HorizontalPan(isEnabled: isSelecting, action: handleDragSelect))
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { scrollFrame = $0 }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            ScrollMetrics(
                offset: geo.contentOffset.y,
                insetTop: geo.contentInsets.top,
                maxOffset: max(
                    geo.contentSize.height - geo.containerSize.height + geo.contentInsets.bottom,
                    -geo.contentInsets.top
                )
            )
        } action: { _, metrics in
            scrollMetrics = metrics
        }
        .scrollDisabled(dragSelect != nil)
        .task(id: dragSelect != nil) { await autoScroll() }
        .sensoryFeedback(.selection, trigger: selection.count) { _, _ in dragSelect != nil }
        .overlay {
            if library.isLoaded && library.assets.isEmpty {
                ContentUnavailableView("ยังไม่มีรูปหรือวีดีโอ", systemImage: "photo")
            }
        }
        .overlay {
            if library.isMeasuring && library.sortOrder == .largest {
                ProgressView("กำลังคำนวณขนาดไฟล์…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(alignment: .top) {
            if let toast { ToastView(text: toast) }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                        selectionBarTop = $0
                    }
                    .onDisappear { selectionBarTop = nil }
            }
        }
        .task(id: selection) {
            await library.measure(selectedAssets)
        }
    }

    private func cell(for asset: PHAsset) -> some View {
        let id = asset.localIdentifier
        let selected = selection.contains(id)
        let size = library.sortOrder == .largest ? library.sizes[id].map(Self.format) : nil
        let activate = {
            if !isSelecting {
                viewer = ViewerTarget(id: id)
            } else if selected {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
        // A tap gesture rather than a Button: Button still fires when a
        // drag-select ends within its touch slop, re-toggling the start cell.
        return AssetThumbnail(
            asset: asset,
            manager: library.imageManager,
            isSelecting: isSelecting,
            isSelected: selected,
            sizeText: size
        )
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: asset))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, activate)
        .accessibilityHint(isSelecting ? "แตะเพื่อเลือกหรือยกเลิก" : "แตะเพื่อดูเต็มจอ")
    }

    /// Drag sideways across cells to select (or deselect) a range, like Photos.
    /// `HorizontalPan` only begins on sideways movement, so vertical drags scroll.
    /// Points are in screen coordinates: the finger stays put while auto-scroll
    /// moves the content under it, so the cell is recomputed from `gridFrame`.
    private func handleDragSelect(_ phase: HorizontalPan.Phase) {
        switch phase {
        case let .began(start, location):
            guard let startIndex = index(at: start) else { return }
            let id = library.assets[startIndex].localIdentifier
            dragSelect = DragSelect(
                startIndex: startIndex,
                adding: !selection.contains(id),
                base: selection
            )
            fingerLocation = location
            updateDragSelection()
        case let .changed(location):
            fingerLocation = location
            updateDragSelection()
        case .ended:
            dragSelect = nil
            fingerLocation = nil
        }
    }

    private func updateDragSelection() {
        guard let drag = dragSelect,
              let finger = fingerLocation,
              let current = index(at: finger) else { return }
        let updated = GridSelection.select(
            ids: library.assets.map(\.localIdentifier),
            from: drag.startIndex, to: current, adding: drag.adding, base: drag.base
        )
        if updated != selection { selection = updated }
    }

    /// While drag-selecting, scrolls when the finger is near the top or bottom
    /// edge, faster the closer it gets, and extends the selection as rows pass.
    private func autoScroll() async {
        guard dragSelect != nil else { return }
        let edge = Self.autoScrollEdge
        while !Task.isCancelled {
            if let finger = fingerLocation {
                let m = scrollMetrics
                // Visible band on screen: below the nav bar (the ScrollView's
                // reported frame already starts there), above the selection bar.
                let visibleTop = scrollFrame.minY
                let visibleBottom = selectionBarTop ?? scrollFrame.maxY
                let step = GridSelection.autoScrollStep(
                    fingerY: finger.y, visibleTop: visibleTop, visibleBottom: visibleBottom,
                    edge: edge, maxStep: Self.autoScrollMaxStep
                )
                let target = min(max(m.offset + step, -m.insetTop), m.maxOffset)
                // scrollTo(y:) takes a point in content coordinates (0 = top of
                // content), while contentOffset includes the top inset.
                if target != m.offset { scrollPosition.scrollTo(y: target + m.insetTop) }
                updateDragSelection()
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Maps a point in viewport coordinates to an asset index, using the same
    /// column math as `GridItem.adaptive`. Points above or below the grid clamp
    /// to the first or last row.
    private func index(at viewportPoint: CGPoint) -> Int? {
        GridSelection.index(at: viewportPoint, gridFrame: gridFrame, itemCount: library.assets.count,
                            minCellSize: Self.cellMinSize, spacing: Self.cellSpacing)
    }

    private var limitedBanner: some View {
        HStack {
            Text("คุณให้สิทธิ์เข้าถึงแค่บางรูป")
                .font(.subheadline)
            Spacer()
            Button("จัดการ") {
                guard let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first else { return }
                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Selection

    private var selectedAssets: [PHAsset] {
        library.assets.filter { selection.contains($0.localIdentifier) }
    }

    private var selectedSizeText: String {
        let sizes = selectedAssets.map { library.sizes[$0.localIdentifier] }
        if sizes.contains(where: { $0 == nil }) { return "กำลังคำนวณขนาด…" }
        return "รวม " + Self.format(sizes.reduce(0) { $0 + ($1 ?? 0) })
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("เลือก \(selection.count) รายการ").font(.headline)
                if !selection.isEmpty {
                    Text(selectedSizeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                Task { await deleteSelected() }
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Label("ลบ", systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(selection.isEmpty || isDeleting)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func deleteSelected() async {
        let targets = selectedAssets
        let freed = targets.reduce(Int64(0)) { $0 + (library.sizes[$1.localIdentifier] ?? 0) }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await library.delete(targets)
            selection.removeAll()
            isSelecting = false
            show("ลบ \(targets.count) รายการ (\(Self.format(freed))) กู้คืนได้ในอัลบั้ม \"ลบล่าสุด\" ภายใน 30 วัน")
        } catch let error as PHPhotosError where error.code == .userCancelled {
            // User tapped "Don't Allow" in the system prompt; keep the selection.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if library.hasAccess {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("เรียงตาม", selection: $library.sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("เรียงตาม", systemImage: "arrow.up.arrow.down")
                }
                .disabled(isDeleting)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "เสร็จ" : "เลือก") {
                    isSelecting.toggle()
                    if !isSelecting { selection.removeAll() }
                }
                .disabled(library.assets.isEmpty || isDeleting)
            }
        }
    }

    // MARK: - Formatting

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func accessibilityLabel(for asset: PHAsset) -> String {
        let date = asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
        if asset.mediaType == .video {
            return "วีดีโอ \(AssetThumbnail.duration(asset.duration)), \(date)"
        }
        return "รูปภาพ, \(date)"
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
