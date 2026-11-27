import Photos
import SwiftUI

/// The พื้นที่ tab: how full the device is, how much of it the photo library
/// takes, and which kinds of media take the most.
struct StorageView: View {
    let library: PhotoLibrary

    private struct Totals {
        var photos: (count: Int, bytes: Int64) = (0, 0)
        var videos: (count: Int, bytes: Int64) = (0, 0)
        var categories: [MediaCategory: (count: Int, bytes: Int64)] = [:]
    }

    @State private var capacity: (total: Int64, free: Int64)?
    @State private var totals: Totals?

    private var breakdown: StorageBreakdown? {
        guard let capacity, let totals else { return nil }
        return StorageBreakdown(total: capacity.total, free: capacity.free,
                                photos: totals.photos.bytes, videos: totals.videos.bytes)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    overview
                } footer: {
                    Text("iOS ไม่อนุญาตให้แอปดูว่าแอปอื่นใช้พื้นที่เท่าไหร่ \"แอปและอื่นๆ\" จึงรวมแอป ระบบ และข้อมูลอื่นที่ไม่ใช่รูปภาพกับวีดีโอ")
                }
                if let totals {
                    Section {
                        mediaRow("รูปภาพ", systemImage: "photo", color: .blue, value: totals.photos)
                        mediaRow("วีดีโอ", systemImage: "video", color: .purple, value: totals.videos)
                    } header: {
                        Text("คลังรูปภาพ")
                    } footer: {
                        Text("ขนาดคิดจากไฟล์ต้นฉบับ ถ้าเปิด \"ปรับพื้นที่จัดเก็บให้เหมาะสม\" ไว้ บางไฟล์อาจเก็บอยู่ใน iCloud และใช้พื้นที่ในเครื่องน้อยกว่านี้")
                    }
                    ForEach(MediaCategory.Section.allCases, id: \.self) { section in
                        Section("\(section.title)แยกตามประเภท") {
                            ForEach(sorted(MediaCategory.categories(in: section), by: totals)) { category in
                                categoryRow(category, value: totals.categories[category] ?? (0, 0))
                            }
                        }
                    }
                }
            }
            .navigationTitle("พื้นที่")
            .navigationDestination(for: MediaCategory.self) { category in
                CategoryGridScreen(library: library, category: category)
            }
            .refreshable { await refresh() }
        }
        // Recount whenever the library changes (adds, deletes, edits).
        .task(id: library.revision) { await refresh() }
    }

    private func refresh() async {
        capacity = StorageBreakdown.deviceCapacity()
        guard library.isLoaded else { return }
        let all = library.assets
        let byCategory = Dictionary(uniqueKeysWithValues: MediaCategory.allCases.map {
            ($0, library.assets(in: $0))
        })
        await library.measure(all + byCategory.values.flatMap { $0 })
        guard !Task.isCancelled else { return }

        func sum(_ list: [PHAsset]) -> (count: Int, bytes: Int64) {
            (list.count, list.reduce(0) { $0 + (library.sizes[$1.localIdentifier] ?? 0) })
        }
        var result = Totals()
        result.photos = sum(all.filter { $0.mediaType == .image })
        result.videos = sum(all.filter { $0.mediaType == .video })
        for (category, list) in byCategory { result.categories[category] = sum(list) }
        totals = result
        // Free space may have changed while measuring.
        capacity = StorageBreakdown.deviceCapacity()
    }

    private func sorted(_ categories: [MediaCategory], by totals: Totals) -> [MediaCategory] {
        categories.sorted { (totals.categories[$0]?.bytes ?? 0) > (totals.categories[$1]?.bytes ?? 0) }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let capacity {
                VStack(alignment: .leading, spacing: 2) {
                    Text("เหลือว่าง").font(.subheadline).foregroundStyle(.secondary)
                    Text(capacity.free.fileSizeText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("ใช้ไป \((capacity.total - capacity.free).fileSizeText) จาก \(capacity.total.fileSizeText)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storage-free")

                if let breakdown {
                    bar(breakdown)
                    VStack(spacing: 8) {
                        legendRow("รูปภาพ", color: .blue, bytes: breakdown.photos, of: breakdown)
                        legendRow("วีดีโอ", color: .purple, bytes: breakdown.videos, of: breakdown)
                        legendRow("แอปและอื่นๆ", color: .gray, bytes: breakdown.other, of: breakdown)
                        legendRow("ว่าง", color: Color(.tertiarySystemFill), bytes: breakdown.free, of: breakdown)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("กำลังคำนวณขนาดรูปและวีดีโอ…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("อ่านขนาดพื้นที่ของเครื่องไม่ได้")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func bar(_ b: StorageBreakdown) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(zip([b.photos, b.videos, b.other], [Color.blue, .purple, .gray]).enumerated()), id: \.offset) { _, item in
                    if item.0 > 0 {
                        item.1.frame(width: max(2, proxy.size.width * b.fraction(item.0)))
                    }
                }
                Color(.tertiarySystemFill)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func legendRow(_ title: String, color: Color, bytes: Int64, of b: StorageBreakdown) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title)
            Spacer(minLength: 8)
            Text(bytes.fileSizeText).monospacedDigit()
            Text(percentText(b.fraction(bytes)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// "<1%" for a small but non-empty share, so it doesn't read as nothing.
    private func percentText(_ fraction: Double) -> String {
        if fraction > 0 && fraction < 0.01 { return "<1%" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Rows

    private func mediaRow(_ title: String, systemImage: String, color: Color,
                          value: (count: Int, bytes: Int64)) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(value.count) รายการ").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(value.bytes.fileSizeText).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func categoryRow(_ category: MediaCategory, value: (count: Int, bytes: Int64)) -> some View {
        NavigationLink(value: category) {
            HStack(spacing: 14) {
                Image(systemName: category.systemImage)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                    Text("\(value.count) รายการ").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(value.count == 0 ? "–" : value.bytes.fileSizeText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(value.count == 0)
        .opacity(value.count == 0 ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storage-\(category.rawValue)")
    }
}
