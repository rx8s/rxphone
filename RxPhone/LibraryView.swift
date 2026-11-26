import Photos
import PhotosUI
import SwiftUI

struct LibraryView: View {
    @State private var library = PhotoLibrary()
    @State private var isSelecting = false
    @State private var selection: Set<String> = []
    @State private var isDeleting = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var viewer: ViewerTarget?

    private struct ViewerTarget: Identifiable { let id: String }

    /// State of a finger dragging across the grid in selection mode.
    private struct DragSelect {
        /// False when the drag started vertically: it belongs to scrolling.
        let isActive: Bool
        var startIndex = 0
        /// Select or deselect, decided by the cell the drag started on.
        var adding = true
        /// Selection before the drag, so cells that leave the range revert.
        var base: Set<String> = []
    }

    @State private var dragSelect: DragSelect?
    @State private var gridWidth: CGFloat = 0

    private static let cellMinSize: CGFloat = 100
    private static let cellSpacing: CGFloat = 2
    private let columns = [GridItem(.adaptive(minimum: cellMinSize), spacing: cellSpacing)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("คลัง")
                .toolbar { toolbar }
        }
        .task { await library.start() }
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

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .notDetermined:
            ContentUnavailableView {
                Label("เข้าถึงคลังรูปภาพ", systemImage: "photo.on.rectangle")
            } description: {
                Text("RxPhone ต้องใช้สิทธิ์เข้าถึงคลังรูปภาพเพื่อแสดงและจัดการรูปกับวีดีโอของคุณ")
            } actions: {
                Button("อนุญาตการเข้าถึง") { Task { await library.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        case .denied, .restricted:
            ContentUnavailableView {
                Label("ไม่มีสิทธิ์เข้าถึงรูปภาพ", systemImage: "lock")
            } description: {
                Text("เปิดสิทธิ์ได้ที่ การตั้งค่า > RxPhone > รูปภาพ")
            } actions: {
                Button("เปิดการตั้งค่า") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            if library.status == .limited { limitedBanner }
            LazyVGrid(columns: columns, spacing: Self.cellSpacing) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    cell(for: asset)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            .simultaneousGesture(dragSelectGesture, including: isSelecting ? .all : .subviews)
        }
        .scrollDisabled(dragSelect?.isActive == true)
        .sensoryFeedback(.selection, trigger: selection.count) { _, _ in dragSelect?.isActive == true }
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
            if isSelecting { selectionBar }
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
    /// A drag that starts vertically is left to the ScrollView.
    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if dragSelect == nil {
                    let t = value.translation
                    guard abs(t.width) > abs(t.height),
                          let start = index(at: value.startLocation) else {
                        dragSelect = DragSelect(isActive: false)
                        return
                    }
                    let id = library.assets[start].localIdentifier
                    dragSelect = DragSelect(
                        isActive: true,
                        startIndex: start,
                        adding: !selection.contains(id),
                        base: selection
                    )
                }
                guard let drag = dragSelect, drag.isActive,
                      let current = index(at: value.location) else { return }
                let range = min(drag.startIndex, current)...max(drag.startIndex, current)
                let ids = Set(library.assets[range].map(\.localIdentifier))
                selection = drag.adding ? drag.base.union(ids) : drag.base.subtracting(ids)
            }
            .onEnded { _ in dragSelect = nil }
    }

    /// Maps a point in the grid's own coordinates to an asset index, using the
    /// same column math as `GridItem.adaptive`.
    private func index(at point: CGPoint) -> Int? {
        guard gridWidth > 0, !library.assets.isEmpty, point.y >= 0 else { return nil }
        let spacing = Self.cellSpacing
        let columnCount = max(Int((gridWidth + spacing) / (Self.cellMinSize + spacing)), 1)
        let cellSize = (gridWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        let column = min(max(Int(point.x / (cellSize + spacing)), 0), columnCount - 1)
        let row = Int(point.y / (cellSize + spacing))
        return min(row * columnCount + column, library.assets.count - 1)
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

private struct ToastView: View {
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
