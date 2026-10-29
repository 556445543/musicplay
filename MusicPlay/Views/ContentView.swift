import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine

    @State private var selection: SidebarItem? = .allTracks
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var keyMonitor: Any?

    private var visibleTracks: [Track] {
        var result = library.tracks

        if case .folder(let folder)? = selection {
            result = result.filter { $0.isInside(folder: folder) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { track in
                track.title.localizedCaseInsensitiveContains(query)
                    || track.artist.localizedCaseInsensitiveContains(query)
                    || track.album.localizedCaseInsensitiveContains(query)
            }
        }

        return result
    }

    private var title: String {
        if case .folder(let folder)? = selection {
            return folder.lastPathComponent
        }
        return "所有歌曲"
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                TrackListView(
                    title: title,
                    tracks: visibleTracks,
                    isScanning: library.isScanning,
                    isLibraryEmpty: library.folders.isEmpty,
                    hasActiveSearch: hasActiveSearch,
                    searchText: $searchText,
                    onPlay: { track in
                        player.play(track, in: visibleTracks)
                    }
                )
            }
            .navigationSplitViewStyle(.balanced)

            PlayerBar(fallbackQueue: visibleTracks.isEmpty ? library.tracks : visibleTracks)
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
