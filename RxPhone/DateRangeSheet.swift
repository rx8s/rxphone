import Photos
import SwiftUI

/// Picks a date range and selects every item taken in it, so a whole trip or
/// month can be deleted in one go. Deleting still goes through the selection
/// bar and iOS's own confirmation.
struct DateRangeSheet: View {
    let assets: [PHAsset]
    let onSelect: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from: Date
    @State private var to: Date

    init(assets: [PHAsset], onSelect: @escaping (Set<String>) -> Void) {
        self.assets = assets
        self.onSelect = onSelect
        let dates = assets.compactMap(\.creationDate)
        // Start on the most recent day, the range people usually want.
        let latest = dates.max() ?? .now
        _from = State(initialValue: latest)
        _to = State(initialValue: latest)
    }

    private var matches: [String] {
        GridSelection.ids(in: assets.map { ($0.localIdentifier, $0.creationDate) }, from: from, to: to)
    }

    var body: some View {
        let count = matches.count
        NavigationStack {
            Form {
                Section {
                    DatePicker("ตั้งแต่", selection: $from, displayedComponents: .date)
                    DatePicker("ถึง", selection: $to, in: from..., displayedComponents: .date)
                } footer: {
                    Text("รวมทั้งวันแรกและวันสุดท้าย รายการที่เลือกไว้แล้วจะยังถูกเลือกอยู่")
                }
                Section {
                    LabeledContent("พบ", value: "\(count) รายการ")
                        .accessibilityIdentifier("date-range-count")
                }
            }
            .navigationTitle("เลือกตามช่วงวันที่")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เลือก") {
                        onSelect(Set(matches))
                        dismiss()
                    }
                    .disabled(count == 0)
                }
            }
            // Keep "to" on or after "from" when "from" moves past it.
            .onChange(of: from) { if to < from { to = from } }
        }
        .presentationDetents([.medium])
    }
}
