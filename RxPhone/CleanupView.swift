import Photos
import SwiftUI

struct CleanupView: View {
    let library: PhotoLibrary
    @State private var scanner = CleanupScanner()

    private struct SyncKey: Equatable {
        let revision: Int
        let isScanning: Bool
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    summary
                    ForEach(CleanupCategory.allCases, id: \.self) { category in
                        card(for: category)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ทำความสะอาด")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await scanner.scan(library) } } label: {
                        Label("สแกนใหม่", systemImage: "arrow.clockwise")
                    }
                    .disabled(scanner.isScanning)
                }
            }
            .navigationDestination(for: CleanupCategory.self) { category in
                CleanupDetailView(category: category, scanner: scanner, library: library)
            }
        }
        .task(id: library.isLoaded) {
            if library.isLoaded && scanner.state == .idle { await scanner.scan(library) }
        }
        // Re-runs on every library change and when a scan ends, so changes
        // made during a scan are caught too.
        .task(id: SyncKey(revision: library.revision, isScanning: scanner.isScanning)) {
            await scanner.sync(with: library)
        }
    }

    // MARK: - Summary

    private func total(_ category: CleanupCategory) -> (count: Int, bytes: Int64) {
        let assets = scanner.assets(in: category)
        return (assets.count, assets.reduce(0) { $0 + (library.sizes[$1.localIdentifier] ?? 0) })
    }

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch scanner.state {
            case .idle, .scanning(_, 0):
                Text("กำลังสแกนคลังรูปภาพ…").font(.headline)
                ProgressView()
            case let .scanning(done, total):
                Text("กำลังหารูปซ้ำ…").font(.headline)
                ProgressView(value: Double(done), total: Double(total))
                Text("\(done) / \(total) รูป")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .finished:
                let totals = CleanupCategory.allCases.map(total)
                let count = totals.reduce(0) { $0 + $1.count }
                let bytes = totals.reduce(Int64(0)) { $0 + $1.bytes }
                Text("ลบได้สูงสุด").font(.subheadline).foregroundStyle(.secondary)
                Text(bytes.fileSizeText)
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Text(count == 0 ? "ไม่พบรายการที่ควรลบ" : "จาก \(count) รายการ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if scanner.skippedInCloud > 0 {
                    Label("ข้าม \(scanner.skippedInCloud) รูปที่อยู่ใน iCloud ตอนหารูปซ้ำ (ไม่ดาวน์โหลดเพื่อประหยัดเน็ต)",
                          systemImage: "icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cards

    private func card(for category: CleanupCategory) -> some View {
        let (count, bytes) = total(category)
        let isEmpty = scanner.state == .finished && count == 0
        return NavigationLink(value: category) {
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(category.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if scanner.state == .finished {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isEmpty ? "ไม่พบ" : bytes.fileSizeText)
                            .font(.headline)
                            .monospacedDigit()
                        if !isEmpty {
                            Text("\(count) รายการ")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(scanner.state != .finished || isEmpty)
        .opacity(isEmpty ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

/// Lists one category's items for review. Duplicates come pre-selected except
/// the copy to keep; other categories start with nothing selected.
struct CleanupDetailView: View {
    let category: CleanupCategory
    let scanner: CleanupScanner
    let library: PhotoLibrary

    @State private var selection: Set<String> = []
    @State private var didPreselect = false
    /// Duplicate copies shown so far; copies outside it are new from a rescan.
    @State private var seenDuplicates: Set<String> = []
    @State private var isDeleting = false
    @State private var toast: String?
    @State private var errorMessage: String?
    @State private var warnTrigger = 0

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 2)]

    private var sections: [[PHAsset]] {
        category == .duplicates ? scanner.duplicateGroups : [scanner.assets(in: category)].filter { !$0.isEmpty }
    }

    private var flatAssets: [PHAsset] { sections.flatMap { $0 } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 6) {
                        if category == .duplicates, let first = section.first {
                            Text("\(section.count) รูปเหมือนกัน · \(first.pixelWidth)×\(first.pixelHeight)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal)
                        }
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section, id: \.localIdentifier) { asset in
                                cell(asset, in: section)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .overlay {
            if flatAssets.isEmpty {
                ContentUnavailableView("ไม่มีรายการ", systemImage: "checkmark.circle",
                                       description: Text("หมวดนี้สะอาดแล้ว"))
            }
        }
        .overlay(alignment: .top) {
            if let toast { ToastView(text: toast) }
        }
        .safeAreaInset(edge: .bottom) {
            if !flatAssets.isEmpty { deleteBar }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { selectAllButton }
        }
        .sensoryFeedback(.warning, trigger: warnTrigger)
        .onAppear(perform: preselect)
        .onChange(of: flatAssets.map(\.localIdentifier)) { _, ids in
            guard category == .duplicates else {
                // Items deleted elsewhere must not stay selected.
                selection.formIntersection(ids)
                return
            }
            let groups = scanner.duplicateGroups.map { $0.map(\.localIdentifier) }
            selection = CleanupRules.refreshDuplicateSelection(
                groups: groups, selection: selection, seen: seenDuplicates
            )
            seenDuplicates.formUnion(ids)
        }
        .alert("ลบไม่สำเร็จ", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hint: String {
        switch category {
        case .duplicates: "รูปที่ติ๊ก ✓ จะถูกลบ แต่ละกลุ่มจะเก็บไว้อย่างน้อย 1 รูป (รูปที่ชื่นชอบหรือรูปที่เก่าที่สุด)"
        case .largeVideos: "เรียงจากไฟล์ใหญ่ที่สุด แตะเพื่อเลือกวีดีโอที่ต้องการลบ"
        case .screenshots: "เรียงจากใหม่ไปเก่า แตะเพื่อเลือกภาพที่ต้องการลบ"
        }
    }

    // MARK: Cells

    private func cell(_ asset: PHAsset, in section: [PHAsset]) -> some View {
        let id = asset.localIdentifier
        let selected = selection.contains(id)
        let label: String? = switch category {
        case .duplicates: selected ? nil : "เก็บไว้"
        case .largeVideos, .screenshots: library.sizes[id]?.fileSizeText
        }
        return AssetThumbnail(
            asset: asset,
            manager: library.imageManager,
            isSelecting: true,
            isSelected: selected,
            sizeText: label
        )
        .onTapGesture { toggle(asset, in: section) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.mediaType == .video ? "วีดีโอ" : "รูปภาพ")
        .accessibilityValue(label ?? "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { toggle(asset, in: section) }
    }

    private func toggle(_ asset: PHAsset, in section: [PHAsset]) {
        let id = asset.localIdentifier
        if selection.contains(id) {
            selection.remove(id)
            return
        }
        if category == .duplicates,
           !CleanupRules.canSelect(id, in: section.map(\.localIdentifier), selection: selection) {
            warnTrigger += 1
            show("ต้องเก็บไว้อย่างน้อย 1 รูปในแต่ละกลุ่ม")
            return
        }
        selection.insert(id)
    }

    private func preselect() {
        guard !didPreselect else { return }
        didPreselect = true
        if category == .duplicates {
            selection = Set(scanner.assets(in: .duplicates).map(\.localIdentifier))
            seenDuplicates = Set(flatAssets.map(\.localIdentifier))
        }
    }

    @ViewBuilder
    private var selectAllButton: some View {
        let defaultSelection = category == .duplicates
            ? Set(scanner.assets(in: .duplicates).map(\.localIdentifier))
            : Set(flatAssets.map(\.localIdentifier))
        if selection == defaultSelection && !selection.isEmpty {
            Button("ไม่เลือก") { selection.removeAll() }
        } else {
            Button(category == .duplicates ? "เลือกรูปซ้ำทั้งหมด" : "เลือกทั้งหมด") {
                selection = defaultSelection
            }
            .disabled(defaultSelection.isEmpty)
        }
    }

    // MARK: Delete

    private var selectedAssets: [PHAsset] {
        flatAssets.filter { selection.contains($0.localIdentifier) }
    }

    private var deleteBar: some View {
        let bytes = selectedAssets.reduce(Int64(0)) { $0 + (library.sizes[$1.localIdentifier] ?? 0) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("เลือก \(selection.count) รายการ")
                    .font(.headline)
                    .accessibilityIdentifier("selection-count")
                if !selection.isEmpty {
                    Text("รวม " + bytes.fileSizeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                Task { await deleteSelected() }
            } label: {
                if isDeleting {
                    // White to stay visible on the red button; the default
                    // gray spinner almost disappears on it.
                    ProgressView().tint(.white)
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
        let bytes = targets.reduce(Int64(0)) { $0 + (library.sizes[$1.localIdentifier] ?? 0) }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await library.delete(targets)
            let ids = Set(targets.map(\.localIdentifier))
            scanner.remove(ids)
            selection.subtract(ids)
            show("ลบ \(targets.count) รายการ (\(bytes.fileSizeText)) กู้คืนได้ในอัลบั้ม \"ลบล่าสุด\" ภายใน 30 วัน")
        } catch let error as PHPhotosError where error.code == .userCancelled {
            // Declined in the system prompt; keep the selection.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

extension Int64 {
    var fileSizeText: String { Self.fileSizeFormatter.string(fromByteCount: self) }

    /// Writes "0 KB" rather than "Zero KB".
    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
