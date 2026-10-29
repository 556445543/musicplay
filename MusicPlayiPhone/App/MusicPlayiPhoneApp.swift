import SwiftUI

@main
struct MusicPlayiPhoneApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileLibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .task {
                    await library.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await library.refresh() }
                }
        }
    }
}
