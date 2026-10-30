import SwiftUI

@main
struct MusicPlayiPhoneApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()
    @StateObject private var lyricsLibrary = LyricsLibrary()
    @StateObject private var activity = LibraryActivityStore.shared
    @StateObject private var lyricsOffsets = LyricsOffsetStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileLibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(lyricsLibrary)
                .environmentObject(activity)
                .environmentObject(lyricsOffsets)
                .task {
                    player.restoreLastSession(in: library.tracks)
                    await library.refresh()
                    player.restoreLastSession(in: library.tracks)
                }
                .task(id: library.folders) {
                    lyricsLibrary.updateFolders(library.folders)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await library.refresh()
                            lyricsLibrary.refreshIndex()
                        }
                    } else {
                        player.saveSessionNow()
                    }
                }
        }
    }
}
