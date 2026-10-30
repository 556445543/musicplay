import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var activity: LibraryActivityStore

    @State private var selection: SidebarItem? = .allTracks
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var showLyrics = true
    @State private var keyMonitor: Any?
    @AppStorage(TrackSortStorage.optionKey) private var sortOptionRaw = TrackSortOption.title.rawValue
    @AppStorage(TrackSortStorage.ascendingKey) private var sortAscending = true

    private var sort: TrackSort {
        TrackSort(option: TrackSortOption(rawValue: sortOptionRaw) ?? .title, ascending: sortAscending)
    }

    private var sortBinding: Binding<TrackSort> {
        Binding(
            get: { sort },
            set: { newValue in
                sortOptionRaw = newValue.option.rawValue
                sortAscending = newValue.ascending
            }
        )
    }

    private var isRecentList: Bool {
        selection == .recent
    }

    private var visibleTracks: [Track] {
        var result: [Track]

        switch selection {
        case .favorites:
            result = library.tracks.filter { activity.isFavorite($0) }
        case .recent:
            let byID = Dictionary(library.tracks.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
            result = activity.recentTrackIDs.compactMap { byID[$0] }
        case .folder(let folder)?:
            result = library.tracks.filter { $0.isInside(folder: folder) }
        case .allTracks?, nil:
            result = library.tracks
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { TrackSearch.matches($0, query: query) }
        }

        // 最近播放保持时间倒序，其余视图按当前排序方式排列。
        if isRecentList {
            return result
        }
        return TrackSorter.sorted(result, by: sort)
    }

    private var title: String {
        switch selection {
        case .favorites:
            return "我喜欢的音乐"
        case .recent:
            return "最近播放"
        case .folder(let folder)?:
            return folder.lastPathComponent
        case .allTracks?, nil:
            return "所有歌曲"
        }
    }

    private var emptyDescription: (icon: String, title: String, message: String) {
        switch selection {
        case .favorites:
            return ("heart", "还没有喜欢的歌曲", "点歌曲右侧的爱心，或右键选择“喜欢”，就会收藏到这里。")
        case .recent:
            return ("clock.arrow.circlepath", "还没有播放记录", "播放过的歌曲会按时间顺序出现在这里。")
        default:
            return ("music.note", "这里还没有歌曲", "换一个文件夹，或点击右上角重新扫描资料库。")
        }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let displayedTracks = visibleTracks

        return VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                TrackListView(
                    title: title,
                    tracks: displayedTracks,
                    isScanning: library.isScanning,
                    isLibraryEmpty: library.folders.isEmpty,
                    hasActiveSearch: hasActiveSearch,
                    searchText: $searchText,
                    sort: sortBinding,
                    allowsSorting: !isRecentList,
                    favoriteIDs: activity.favoriteIDs,
                    currentTrackID: player.currentTrack?.id,
                    isPlaying: player.isPlaying,
                    emptyIcon: emptyDescription.icon,
                    emptyTitle: emptyDescription.title,
                    emptyMessage: emptyDescription.message,
                    onPlay: { track in
                        player.play(track, in: displayedTracks)
                    },
                    onToggleFavorite: { track in
                        activity.toggleFavorite(track)
                    }
                )
                .equatable()
            }
            .navigationSplitViewStyle(.balanced)
            .inspector(isPresented: $showLyrics) {
                LyricsPane()
                    .inspectorColumnWidth(min: 280, ideal: 340, max: 480)
            }

            PlayerBar(
                fallbackQueue: displayedTracks.isEmpty ? library.tracks : displayedTracks,
                showLyrics: $showLyrics
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.addFolders(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .onAppear {
            installKeyMonitor()
            clearInitialSearchFocus()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }
        .alert("无法播放", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    private func clearInitialSearchFocus() {
        for delay in [0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }),
                      let editor = window.firstResponder as? NSTextView,
                      editor.string.isEmpty else { return }
                window.makeFirstResponder(nil)
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            if !event.isARepeat {
                player.togglePlayPause(fallbackQueue: library.tracks)
            }
            return nil
        }
    }
}

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.07))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                Text("松开以导入音乐文件夹")
                    .font(.headline)
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .allowsHitTesting(false)
    }
}
