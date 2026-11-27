import Photos
import SwiftUI

/// The หมวดหมู่ tab: Live Photos, selfies, screenshots, screen recordings and
/// other kinds of media iOS recognises, each opening its own grid.
struct CategoriesView: View {
    let library: PhotoLibrary

    private struct Summary {
        let count: Int
        let cover: PHAsset?
    }

    @State private var summaries: [MediaCategory: Summary] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(MediaCategory.Section.allCases, id: \.self) { section in
                    Section(section.title) {
                        ForEach(MediaCategory.categories(in: section)) { category in
                            row(category)
                        }
                    }
                }
            }
            .navigationTitle("หมวดหมู่")
            .navigationDestination(for: MediaCategory.self) { category in
                CategoryGridScreen(library: library, category: category)
            }
        }
        // Recount whenever the library changes (adds, deletes, edits).
        .task(id: library.revision) { refresh() }
    }

    private func refresh() {
        var result: [MediaCategory: Summary] = [:]
        for category in MediaCategory.allCases {
            let assets = library.assets(in: category)
            result[category] = Summary(count: assets.count, cover: assets.first)
        }
        summaries = result
    }

    @ViewBuilder
    private func row(_ category: MediaCategory) -> some View {
        let summary = summaries[category]
        let count = summary?.count ?? 0
        NavigationLink(value: category) {
            HStack(spacing: 14) {
                cover(summary?.cover, category: category)
                Text(category.title)
                Spacer(minLength: 8)
                if summary == nil {
                    ProgressView()
                } else {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(count == 0)
        .opacity(summary != nil && count == 0 ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(category.title)
        .accessibilityValue("\(count) รายการ")
        .accessibilityIdentifier("category-\(category.rawValue)")
    }

    /// The newest item as a small cover, or the category icon when empty.
    @ViewBuilder
    private func cover(_ asset: PHAsset?, category: MediaCategory) -> some View {
        Group {
            if let asset {
                AssetThumbnail(asset: asset, manager: library.imageManager,
                               isSelecting: false, isSelected: false, sizeText: nil,
                               showsDuration: false)
            } else {
                Image(systemName: category.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// One category's photos and videos, with the same select, drag-select and
/// delete as the คลัง tab.
struct CategoryGridScreen: View {
    @Bindable var library: PhotoLibrary
    let category: MediaCategory

    var body: some View {
        AssetGridScreen(library: library, title: category.title,
                        assets: library.assets(in: category), source: .category(category),
                        sort: $library.categorySortOrder)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: library.categorySortOrder) {
                if library.categorySortOrder == .largest {
                    await library.measure(library.assets(in: category))
                }
            }
    }
}
