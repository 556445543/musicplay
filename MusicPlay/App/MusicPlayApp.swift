import SwiftUI

@main
struct MusicPlayApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerEngine()

    var body: some Scene {
        Window("MusicPlay", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .frame(minWidth: 900, minHeight: 580)
                .task { await library.refresh() }
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入音乐文件夹…") {
                    library.importFolders()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("重新扫描资料库") {
                    Task { await library.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("播放") {
                Button(player.isPlaying ? "暂停" : "播放") {
                    player.togglePlayPause(fallbackQueue: library.tracks)
                }

                Divider()

                Button("下一首") {
                    player.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(player.currentTrack == nil)

                Button("上一首") {
                    player.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(player.currentTrack == nil)

                Divider()

                Toggle("随机播放", isOn: Binding(
                    get: { player.shuffleEnabled },
                    set: { player.shuffleEnabled = $0 }
                ))

                Picker("循环播放", selection: Binding(
                    get: { player.repeatMode },
                    set: { player.repeatMode = $0 }
                )) {
                    Text("关闭").tag(RepeatMode.off)
                    Text("全部循环").tag(RepeatMode.all)
                    Text("单曲循环").tag(RepeatMode.one)
                }
            }
        }
    }
}
