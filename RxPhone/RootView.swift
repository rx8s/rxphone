import SwiftUI

/// Owns the shared PhotoLibrary. Shows the permission screens until access is
/// granted, then the tab bar.
struct RootView: View {
    @State private var library = PhotoLibrary()

    var body: some View {
        Group {
            if library.hasAccess {
                TabView {
                    Tab("คลัง", systemImage: "photo.on.rectangle") {
                        LibraryView(library: library)
                    }
                    Tab("ทำความสะอาด", systemImage: "sparkles") {
                        CleanupView(library: library)
                    }
                }
            } else {
                PermissionView(library: library)
            }
        }
        .task { await library.start() }
    }
}

private struct PermissionView: View {
    let library: PhotoLibrary

    var body: some View {
        if library.status == .notDetermined {
            ContentUnavailableView {
                Label("เข้าถึงคลังรูปภาพ", systemImage: "photo.on.rectangle")
            } description: {
                Text("RxPhone ต้องใช้สิทธิ์เข้าถึงคลังรูปภาพเพื่อแสดงและจัดการรูปกับวีดีโอของคุณ")
            } actions: {
                Button("อนุญาตการเข้าถึง") { Task { await library.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
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
        }
    }
}
