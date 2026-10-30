import SwiftUI
import UniformTypeIdentifiers

struct MobileLibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var lyricsLibrary: LyricsLibrary
    @EnvironmentObject private var activity: LibraryActivityStore
    @EnvironmentObject private var lyricsOffsets: LyricsOffsetStore

    @State private var searchText = ""
    @State private var importMode: ImportMode = .files
    @State private var showImporter = false
    @State private var showNowPlaying = false
    @State private var feedback: ImportFeedback?
    @AppStorage("mobileLibraryFilter") private var filterRaw = LibraryFilter.all.rawValue
    @AppStorage(TrackSortStorage.optionKey) private var sortOptionRaw = TrackSortOption.title.rawValue
    @AppStorage(TrackSortStorage.ascendingKey) private var sortAscending = true

    private var filter: LibraryFilter {
        get { LibraryFilter(rawValue: filterRaw) ?? .all }
        nonmutating set { filterRaw = newValue.rawValue }
    }

    private var sort: TrackSort {
        TrackSort(option: TrackSortOption(rawValue: sortOptionRaw) ?? .title, ascending: sortAscending)
    }

    private var baseTracks: [Track] {
        switch filter {
        case .all:
            return library.tracks
        case .favorites:
            return library.tracks.filter { activity.isFavorite($0) }
        case .recent:
            let byID = Dictionary(library.tracks.map { ($0.stableID, $0) }, uniquingKeysWith: { first, _ in first })
            return activity.recentTrackIDs.compactMap { byID[$0] }
        }
    }

    private var hasActiveSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyLibrary
                } else {
                    VStack(spacing: 0) {
                        filterBar

                        if filter != .all && baseTracks.isEmpty && !hasActiveSearch {
                            filterEmptyState
                        } else {
                            MobileTrackList(
                                tracks: baseTracks,
                                searchText: searchText,
                                sort: sort,
                                preservesOrder: filter == .recent,
                                isScanning: library.isScanning,
                                isImporting: library.isImporting,
                                favoriteIDs: activity.favoriteIDs,
                                currentTrackID: player.currentTrack?.id,
                                isPlaying: player.isPlaying,
                                onSortChange: { newValue in
                                    sortOptionRaw = newValue.option.rawValue
                                    sortAscending = newValue.ascending
                                },
                                onPlay: { track, queue in
                                    player.play(track, in: queue)
                                },
                                onToggle: { track, queue in
                                    player.togglePlayPause(fallbackQueue: queue)
                                },
                                onToggleFavorite: { track in
                                    activity.toggleFavorite(track)
                                },
                                onRefresh: {
                                    await library.refresh()
                                    lyricsLibrary.refreshIndex()
                                }
                            )
                            .equatable()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("音乐库")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            beginImport(.files)
                        } label: {
                            Label("导入歌曲", systemImage: "music.note")
                        }
                        Button {
                            beginImport(.folder)
                        } label: {
                            Label("导入文件夹", systemImage: "folder")
                        }
                        Divider()
                        Button {
                            feedback = ImportFeedback(
                                title: "如何导入音乐",
                                message: "点“导入歌曲”后，在文件选择器底部选择“浏览”，找到 MP3、M4A、FLAC、WAV 或 AIFF 文件。也可以连接电脑，在 Finder → iPhone → 文件 → MusicPlay 里直接拖入歌曲。\n\n注意：Apple Music 等流媒体里受版权保护的歌曲不能导入，必须是音乐文件本身。"
                            )
                        } label: {
                            Label("如何导入音乐？", systemImage: "questionmark.circle")
                        }
                        Button {
                            Task {
                                await library.refresh()
                                lyricsLibrary.refreshIndex()
                            }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                        }
                        .disabled(library.isScanning)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .accessibilityLabel("添加音乐")
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索歌名、艺人、专辑或拼音"
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentTrack != nil {
                    MobileMiniPlayer(openPlayer: { showNowPlaying = true })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: player.currentTrack?.id)
            .overlay(alignment: .top) {
                if library.isImporting {
                    importingBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: library.isImporting)
            .alert("无法播放", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importMode.contentTypes,
            allowsMultipleSelection: importMode.allowsMultipleSelection
        ) { result in
            let mode = importMode
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task {
                    let count: Int
                    if mode == .folder, let folder = urls.first {
                        count = await library.importFolder(folder)
                    } else {
                        count = await library.importFiles(urls)
                    }
                    if count > 0 {
                        lyricsLibrary.refreshIndex()
                    }
                    showImportResult(count)
                }
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                feedback = ImportFeedback(title: "无法导入", message: error.localizedDescription)
            }
        }
        .alert(item: $feedback) { feedback in
            Alert(
                title: Text(feedback.title),
                message: Text(feedback.message),
                dismissButton: .default(Text("好"))
            )
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            MobileNowPlayingView()
                .environmentObject(player)
                .environmentObject(lyricsLibrary)
                .environmentObject(activity)
                .environmentObject(lyricsOffsets)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        filter = item
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.title)
                            .font(.footnote.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(
                            filter == item
                                ? Color.accentColor.opacity(0.15)
                                : Color(.secondarySystemBackground)
                        )
                    )
                    .foregroundStyle(filter == item ? Color.accentColor : Color.secondary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var filterEmptyState: some View {
        if filter == .favorites {
            ContentUnavailableView {
                Label("还没有喜欢的歌曲", systemImage: "heart")
            } description: {
                Text("点歌曲右侧的爱心，或在歌曲上左滑、长按即可收藏。")
            }
        } else {
            ContentUnavailableView {
                Label("还没有播放记录", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("播放过的歌曲会按时间顺序出现在这里。")
            }
        }
    }

    private var emptyLibrary: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.38, green: 0.34, blue: 0.78),
                                    Color(red: 0.58, green: 0.32, blue: 0.68),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("把音乐放进口袋")
                        .font(.title2.weight(.bold))
                    Text("从“文件”导入歌曲或整个文件夹，音乐会被复制到 MusicPlay 自己的资料库里。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 12) {
                    Button {
                        beginImport(.files)
                    } label: {
                        Label("导入歌曲", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        beginImport(.folder)
                    } label: {
                        Label("导入文件夹", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 6) {
                    Text("支持 MP3、M4A、FLAC、WAV、AIFF 等格式")
                    Text("导入时在文件选择器底部点“浏览”找到歌曲；也可以用数据线连接电脑，在 Finder → iPhone → 文件 → MusicPlay 里直接拖入。")
                        .multilineTextAlignment(.center)
                }
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 28)

                if library.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在扫描资料库…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var importingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("正在导入歌曲…")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .foregroundStyle(.white)
        .padding(.top, 10)
    }

    private func beginImport(_ mode: ImportMode) {
        importMode = mode
        showImporter = true
    }

    private func showImportResult(_ count: Int) {
        if count > 0 {
            feedback = ImportFeedback(
                title: "导入完成",
                message: "已向资料库添加 \(count) 首歌曲。"
            )
        } else {
            feedback = ImportFeedback(
                title: "没有可导入的歌曲",
                message: "请选择 MP3、M4A、FLAC、WAV 或 AIFF 格式的音频文件。"
            )
        }
    }
}

private struct MobileTrackList: View, Equatable {
    let tracks: [Track]
    let searchText: String
    let sort: TrackSort
    let preservesOrder: Bool
    let isScanning: Bool
    let isImporting: Bool
    let favoriteIDs: Set<String>
    let currentTrackID: String?
    let isPlaying: Bool
    let onSortChange: (TrackSort) -> Void
    let onPlay: (Track, [Track]) -> Void
    let onToggle: (Track, [Track]) -> Void
    let onToggleFavorite: (Track) -> Void
    let onRefresh: () async -> Void

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortBinding: Binding<TrackSort> {
        Binding(get: { sort }, set: onSortChange)
    }

    var body: some View {
        let visibleTracks = Self.filteredTracks(tracks, query: query, sort: sort, preservesOrder: preservesOrder)

        if visibleTracks.isEmpty && !query.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            let grouped = !preservesOrder && sort.option.supportsInitialIndex
            let sections = preservesOrder
                ? [TrackSection(id: "order", tracks: visibleTracks)]
                : TrackSorter.sections(visibleTracks, by: sort)
            let showsIndex = grouped && query.isEmpty && sections.count > 1

            VStack(spacing: 0) {
                listHeader(count: visibleTracks.count)

                ScrollViewReader { proxy in
                    List {
                        ForEach(sections) { section in
                            Section {
                                ForEach(Array(section.tracks.enumerated()), id: \.element.id) { index, track in
                                    trackRow(track, queue: visibleTracks, showsIndex: showsIndex)
                                        .id(index == 0 && grouped ? "letter-\(section.id)" : track.id)
                                }
                            } header: {
                                if grouped {
                                    Text(section.id)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                        .padding(.leading, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await onRefresh()
                    }
                    .overlay(alignment: .trailing) {
                        if showsIndex {
                            AlphabetIndexBar(letters: sections.map(\.id)) { letter in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    proxy.scrollTo("letter-\(letter)", anchor: .top)
                                }
                            }
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
        }
    }

    private func listHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(count) 首歌曲")
            if isScanning || isImporting {
                ProgressView()
                    .controlSize(.mini)
                Text(isImporting ? "正在导入…" : "正在扫描…")
            }

            Spacer(minLength: 8)

            if !preservesOrder {
                Menu {
                    TrackSortMenuContent(sort: sortBinding)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(sort.option.label)
                        Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .contentShape(Capsule())
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("排序方式")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private func trackRow(_ track: Track, queue: [Track], showsIndex: Bool) -> some View {
        MobileTrackRow(
            track: track,
            isCurrent: currentTrackID == track.id,
            isPlaying: isPlaying && currentTrackID == track.id,
            isFavorite: favoriteIDs.contains(track.stableID),
            onToggleFavorite: { onToggleFavorite(track) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if currentTrackID == track.id {
                onToggle(track, queue)
            } else {
                onPlay(track, queue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggleFavorite(track)
            } label: {
                Label(
                    favoriteIDs.contains(track.stableID) ? "取消喜欢" : "喜欢",
                    systemImage: favoriteIDs.contains(track.stableID) ? "heart.slash.fill" : "heart.fill"
                )
            }
            .tint(.pink)
        }
        .contextMenu {
            Button {
                onPlay(track, queue)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            if currentTrackID == track.id {
                Button {
                    onToggle(track, queue)
                } label: {
                    Label(
                        isPlaying ? "暂停" : "继续播放",
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    )
                }
            }
            Button {
                onToggleFavorite(track)
            } label: {
                Label(
                    favoriteIDs.contains(track.stableID) ? "取消喜欢" : "喜欢",
                    systemImage: favoriteIDs.contains(track.stableID) ? "heart.slash" : "heart"
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: showsIndex ? 30 : 16))
        .listRowSeparator(.hidden)
        .listRowBackground(
            currentTrackID == track.id
                ? Color.accentColor.opacity(0.09)
                : Color(.systemBackground)
        )
    }

    private static func filteredTracks(_ tracks: [Track], query: String, sort: TrackSort, preservesOrder: Bool) -> [Track] {
        let filtered: [Track]
        if query.isEmpty {
            filtered = tracks
        } else {
            filtered = tracks.filter { TrackSearch.matches($0, query: query) }
        }
        return preservesOrder ? filtered : TrackSorter.sorted(filtered, by: sort)
    }

    static func == (lhs: MobileTrackList, rhs: MobileTrackList) -> Bool {
        lhs.tracks == rhs.tracks
            && lhs.searchText == rhs.searchText
            && lhs.sort == rhs.sort
            && lhs.preservesOrder == rhs.preservesOrder
            && lhs.isScanning == rhs.isScanning
            && lhs.isImporting == rhs.isImporting
            && lhs.favoriteIDs == rhs.favoriteIDs
            && lhs.currentTrackID == rhs.currentTrackID
            && lhs.isPlaying == rhs.isPlaying
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "喜欢"
        case .recent: return "最近"
        }
    }

    var icon: String {
        switch self {
        case .all: return "music.note.list"
        case .favorites: return "heart.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }
}

private enum ImportMode: Equatable {
    case files
    case folder

    var contentTypes: [UTType] {
        switch self {
        case .files: return [.audio]
        case .folder: return [.folder]
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .files: return true
        case .folder: return false
        }
    }
}

private struct ImportFeedback: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct MobileTrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.url, size: 50, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(track.artist.isEmpty ? "未知艺人" : track.artist)
                    if !track.album.isEmpty {
                        Text("·")
                        Text(track.album)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                if isPlaying {
                    EqualizerBars()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else if track.duration > 0 {
                Text(durationString(track.duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isFavorite ? Color.pink : Color.secondary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "取消喜欢" : "喜欢")
        }
        .padding(.vertical, 2)
    }
}
